import 'dart:async';

import 'package:flutter/widgets.dart';

import '../playback/playback_event.dart';
import '../playback/playback_session_tracker.dart';
import 'telemetry_client.dart';
import 'telemetry_config.dart';
import 'telemetry_queue.dart';

/// Delivers measured playback events to the telemetry API: it is a sink of a
/// [PlaybackSessionTracker] that persists every event and drains the queue
/// against the endpoint.
///
/// The measurement rules (session ids, deltas, seeks, stalls, the `progress`
/// cadence) belong to the tracker; what lives here is transport: the on-disk
/// queue, the batching, the token, the retries and their backoff.
///
/// Created by [CustomPlayerController] when [PlayerConfig.telemetry] is set;
/// host apps do not normally build one themselves.
class TelemetryReporter with WidgetsBindingObserver {
  /// Standalone reporter: it builds and owns its own tracker, and the
  /// measurement hooks below drive it.
  TelemetryReporter(
    this.config, {
    TelemetryQueue? queue,
    TelemetryClient? client,
  })  : _queue = queue ??
            TelemetryQueue(
              maxEvents: config.maxQueuedEvents,
              filePath: config.queueFilePath,
              verbose: config.verbose,
            ),
        _client = client ?? TelemetryClient(config),
        _tracker = PlaybackSessionTracker(options: config.playbackOptions),
        _ownsTracker = true {
    _start();
  }

  /// Attaches to a [tracker] the caller already owns — what
  /// [CustomPlayerController] does, so that one playback is measured once and
  /// every sink (this reporter, [PlayerConfig.onPlaybackEvent]) sees the same
  /// events.
  ///
  /// The tracker is neither started nor disposed here: it outlives the
  /// reporter and its owner closes it.
  TelemetryReporter.forTracker(
    this.config,
    PlaybackSessionTracker tracker, {
    TelemetryQueue? queue,
    TelemetryClient? client,
  })  : _queue = queue ??
            TelemetryQueue(
              maxEvents: config.maxQueuedEvents,
              filePath: config.queueFilePath,
              verbose: config.verbose,
            ),
        _client = client ?? TelemetryClient(config),
        _tracker = tracker,
        _ownsTracker = false {
    _start();
  }

  void _start() {
    _tracker.addSink(_onEvent);
    _observeLifecycle();
    _flushTimer = Timer.periodic(config.flushInterval, (_) => flush());
    // Drain whatever a previous run left behind (process death, offline TV).
    unawaited(flush());
  }

  final TelemetryConfig config;
  final TelemetryQueue _queue;
  final TelemetryClient _client;
  final PlaybackSessionTracker _tracker;

  /// Whether [close] must dispose the tracker — only true when this reporter
  /// created it.
  final bool _ownsTracker;

  /// The layer that measures the session this reporter reports on.
  PlaybackSessionTracker get tracker => _tracker;

  Timer? _flushTimer;

  /// Set once [close] has finished; nothing is measured or sent afterwards.
  bool _disposed = false;

  /// Set as soon as [close] starts: no new sessions, but the final flush of
  /// the queue is still allowed to run.
  bool _closing = false;

  // Serialises writes to the queue, so events reach disk in the order the
  // tracker emitted them.
  Future<void> _queueChain = Future.value();

  // ── Flush state ───────────────────────────────────────────────────────────

  int _consecutiveFailures = 0;
  DateTime? _retryNotBefore;

  // Serialises flushes so a second request queues up behind the running one.
  Future<void> _flushChain = Future.value();

  /// Whether a playback session is currently being measured.
  bool get sessionActive => _tracker.sessionActive;

  /// Id of the session being measured, for diagnostics. Null between sessions.
  String? get sessionId => _tracker.sessionId;

  /// Events waiting to be delivered.
  Future<int> get queuedEventCount => _queue.length;

  // ── Measurement hooks ─────────────────────────────────────────────────────
  //
  // Kept as the reporter's own API for hosts that drive it directly; each one
  // forwards to the tracker, which is what actually measures.

  /// Starts measuring a new playback session — one per media load, repeats of
  /// the same media included.
  void beginSession({required int contentId, int? episodeId}) {
    if (_disposed || _closing) return;
    _tracker.beginSession(contentId: contentId, episodeId: episodeId);
  }

  /// Ends the current session, queueing the deltas that are still pending.
  void endSession() {
    _tracker.endSession();
    unawaited(flush());
  }

  /// A fatal player error: closes the session with the pending deltas.
  void reportError() {
    _tracker.reportError();
    unawaited(flush());
  }

  /// The player reached its first frame / resumed playing.
  void onPlaying(Duration position) => _tracker.onPlaying(position);

  void onPaused(Duration position) => _tracker.onPaused(position);

  /// Position update from the player (~every 300ms while playing).
  void onPosition(Duration position, {required bool playing}) =>
      _tracker.onPosition(position, playing: playing);

  /// Buffering began.
  void onBufferingStart() => _tracker.onBufferingStart();

  /// Buffering ended.
  void onBufferingEnd() => _tracker.onBufferingEnd();

  /// Height of the quality currently being rendered, e.g. 1080.
  void onResolution(int? height) => _tracker.onResolution(height);

  // ── Sink ──────────────────────────────────────────────────────────────────

  /// Persists one measured event and, when it closes a session, delivers what
  /// is queued right away — including sessions the tracker ended on its own
  /// (a new media load, the app being detached).
  void _onEvent(PlaybackEvent event) {
    if (_disposed) return;
    _queueChain = _queueChain.then((_) async {
      await _queue.add(event);
      _log('queued $event');
    }).catchError((Object e) {
      debugPrint('[MkPlayer] telemetry could not queue an event: $e');
    });
    if (event.type == PlaybackEventType.end ||
        event.type == PlaybackEventType.error) {
      unawaited(flush());
    }
  }

  // ── Delivery ──────────────────────────────────────────────────────────────

  /// Sends queued events in batches of at most [TelemetryConfig.maxBatchSize].
  ///
  /// Events are removed only on 204 (accepted) or 422 (never going to work).
  /// 401 keeps the queue for the next login, 429 and network errors keep it for
  /// the next retry window.
  Future<void> flush({bool ignoreBackoff = false}) {
    // Chained rather than skipped: a flush requested while another is in
    // flight (say `end` right after a `progress`) must still run, and run
    // after it, or the last events of a session would sit in the queue.
    final pending =
        _flushChain.then((_) => _flushOnce(ignoreBackoff: ignoreBackoff));
    _flushChain = pending.catchError((Object e) {
      debugPrint('[MkPlayer] telemetry flush failed: $e');
    });
    return pending;
  }

  Future<void> _flushOnce({required bool ignoreBackoff}) async {
    if (_disposed) return;
    final notBefore = _retryNotBefore;
    if (!ignoreBackoff &&
        notBefore != null &&
        DateTime.now().isBefore(notBefore)) {
      return;
    }
    // Let any event emitted a moment ago be measured and reach the queue first.
    await _tracker.settled;
    await _queueChain;
    while (!_disposed) {
      final batch = await _queue.peek(config.maxBatchSize);
      if (batch.isEmpty) {
        _consecutiveFailures = 0;
        _retryNotBefore = null;
        return;
      }
      final result = await _client.send(batch);
      if (result.shouldDrop) {
        await _queue.removeFirst(batch.length);
        _consecutiveFailures = 0;
        _retryNotBefore = null;
        _log('${batch.length} event(s) delivered');
        continue; // a backlog over 50 events goes out in several requests
      }
      switch (result.status) {
        case TelemetryUploadStatus.unauthorized:
        case TelemetryUploadStatus.noToken:
          // Keep everything; updateToken() releases the queue after login.
          _retryNotBefore = DateTime.now().add(const Duration(minutes: 5));
          _log('paused: no valid token, ${batch.length}+ event(s) held');
        case TelemetryUploadStatus.rateLimited:
        case TelemetryUploadStatus.transient:
          _consecutiveFailures++;
          final backoff = result.retryAfter ?? _backoffDelay();
          _retryNotBefore = DateTime.now().add(backoff);
          _log('retry in ${backoff.inSeconds}s (${result.status.name})');
        case TelemetryUploadStatus.accepted:
        case TelemetryUploadStatus.invalid:
          break; // handled by shouldDrop
      }
      return;
    }
  }

  Duration _backoffDelay() {
    final base = config.retryBaseDelay.inMilliseconds;
    final factor = 1 << (_consecutiveFailures - 1).clamp(0, 8);
    return Duration(
      milliseconds:
          (base * factor).clamp(base, const Duration(minutes: 15).inMilliseconds),
    );
  }

  /// Hands the reporter a freshly issued token and drains whatever a 401 was
  /// holding back.
  void updateToken(String? token) {
    _client.updateToken(token);
    _retryNotBefore = null;
    _consecutiveFailures = 0;
    unawaited(flush(ignoreBackoff: true));
  }

  // ── App lifecycle ─────────────────────────────────────────────────────────

  void _observeLifecycle() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // No binding (pure Dart tests): nothing to react to.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back to the foreground: a good moment to retry what went offline. Going
    // away is the tracker's business — it closes the session, and the `end`
    // event that reaches this sink triggers the final flush.
    if (state == AppLifecycleState.resumed) unawaited(flush());
  }

  // ── Disposal ──────────────────────────────────────────────────────────────

  /// Emits the pending `end` event, flushes and releases everything.
  Future<void> close() async {
    if (_disposed || _closing) return;
    _closing = true;
    // A tracker this reporter owns is closed with it; a shared one only gets
    // its session ended — its owner disposes it.
    if (_ownsTracker) {
      _tracker.dispose();
    } else {
      _tracker.endSession();
    }
    _flushTimer?.cancel();
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    // The final `end` is dispatched asynchronously: wait for it to reach the
    // queue before detaching, or it would never be delivered.
    await _tracker.settled;
    _tracker.removeSink(_onEvent);
    await _queueChain;
    await flush(ignoreBackoff: true);
    _disposed = true;
    _client.close();
  }

  void _log(String message) {
    if (config.verbose) debugPrint('[MkPlayer] telemetry: $message');
  }
}
