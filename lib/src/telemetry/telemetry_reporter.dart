import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'telemetry_client.dart';
import 'telemetry_config.dart';
import 'telemetry_event.dart';
import 'telemetry_queue.dart';

/// Turns player events into API telemetry: measures one playback session,
/// emits `start` / `progress` / `end` / `error`, persists every event and
/// drains the queue against the API.
///
/// The reporter owns the rules the backend depends on:
///
/// * every counter is a **delta since the previous event** and is reset to zero
///   once the event is queued — a lost report costs one interval, nothing more;
/// * `occurredAt` always carries a UTC offset, so a queue flushed the next day
///   is still filed under the day it was watched;
/// * a fresh `sessionId` per media load — repeats of the same title included —
///   repeated on every event of that playback;
/// * `progress` only ticks while the video is actually playing in the
///   foreground — never while paused or backgrounded.
///
/// Created by [CustomPlayerController] when [PlayerConfig.telemetry] is set;
/// host apps do not normally build one themselves.
class TelemetryReporter with WidgetsBindingObserver {
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
        _client = client ?? TelemetryClient(config) {
    _observeLifecycle();
    _flushTimer = Timer.periodic(config.flushInterval, (_) => flush());
    // Drain whatever a previous run left behind (process death, offline TV).
    unawaited(flush());
  }

  final TelemetryConfig config;
  final TelemetryQueue _queue;
  final TelemetryClient _client;

  /// Position jumps larger than this are treated as seeks and never counted as
  /// watched time (positions arrive roughly every 300ms while playing).
  static const _seekThreshold = Duration(seconds: 5);

  // ── Session state ─────────────────────────────────────────────────────────

  String? _sessionId;
  int? _contentId;
  int? _episodeId;
  bool _startSent = false;
  bool _sessionActive = false;

  final Stopwatch _startup = Stopwatch();

  // Pending deltas — reset to zero after every emitted event.
  int _watchedMs = 0;
  int _stallCount = 0;
  int _stalledMs = 0;
  int? _bytesBaseline;
  bool _bytesBaselineReady = false;

  Duration _position = Duration.zero;
  Duration? _lastWatchPosition;
  DateTime? _stallStartedAt;
  String? _resolution;
  bool _playing = false;
  bool _foreground = true;

  Timer? _progressTimer;
  Timer? _flushTimer;

  /// Set once [close] has finished; nothing is measured or sent afterwards.
  bool _disposed = false;

  /// Set as soon as [close] starts: no new sessions, but the final flush of
  /// the queue is still allowed to run.
  bool _closing = false;

  // Keeps emitted events in chronological order despite async byte reads.
  Future<void> _emitLock = Future.value();

  // ── Flush state ───────────────────────────────────────────────────────────

  int _consecutiveFailures = 0;
  DateTime? _retryNotBefore;

  // Serialises flushes so a second request queues up behind the running one.
  Future<void> _flushChain = Future.value();

  /// Whether a playback session is currently being measured.
  bool get sessionActive => _sessionActive;

  /// Id of the session being measured, for diagnostics. Null between sessions.
  String? get sessionId => _sessionId;

  /// Events waiting to be delivered.
  Future<int> get queuedEventCount => _queue.length;

  // ── Session lifecycle ─────────────────────────────────────────────────────

  /// Starts measuring a new playback session — one per media load, repeats of
  /// the same media included.
  void beginSession({required int contentId, int? episodeId}) {
    if (_disposed || _closing) return;
    if (contentId < 1) {
      // The API requires contentId >= 1; reporting it would 422 the whole batch.
      debugPrint('[MkPlayer] telemetry: ignoring session with contentId '
          '$contentId (must be >= 1)');
      return;
    }
    // Changing content closes the previous session with its pending deltas.
    if (_sessionActive) endSession();

    _sessionId = _generateSessionId();
    _contentId = contentId;
    _episodeId = episodeId;
    _sessionActive = true;
    _startSent = false;

    _watchedMs = 0;
    _stallCount = 0;
    _stalledMs = 0;
    _bytesBaseline = null;
    _bytesBaselineReady = false;
    _position = Duration.zero;
    _lastWatchPosition = null;
    _stallStartedAt = null;
    _resolution = null;
    _playing = false;

    _progressTimer?.cancel();
    _progressTimer = null;

    // prepare() → first frame.
    _startup
      ..reset()
      ..start();

    // The byte counter is cumulative for the whole player, so the session's
    // baseline is whatever it reads right now.
    unawaited(_readBytesTotal().then((total) {
      if (_bytesBaselineReady) return;
      _bytesBaseline = total;
      _bytesBaselineReady = true;
    }));

    _log('session $_sessionId started '
        '(content $contentId, episode $episodeId)');
  }

  /// Ends the current session, flushing the deltas that are still pending.
  void endSession() {
    if (!_sessionActive) return;
    final wasStarted = _startSent;
    // A session that ends mid-rebuffer still owes that freeze time.
    _stopStallTimer();
    _sessionActive = false;
    _playing = false;
    _progressTimer?.cancel();
    _progressTimer = null;
    _startup.stop();
    // A session that never reached its first frame produced no `start`; there
    // is nothing to close on the server side.
    if (wasStarted) _emit(TelemetryEventType.end);
    _sessionId = null;
    unawaited(flush());
  }

  /// A fatal player error: closes the session with the pending deltas. The
  /// error detail deliberately never leaves for this API — that belongs in
  /// crash reporting.
  void reportError() {
    if (!_sessionActive) return;
    _stopStallTimer();
    _sessionActive = false;
    _playing = false;
    _progressTimer?.cancel();
    _progressTimer = null;
    _startup.stop();
    // Deliberate: a failure before the first frame is NOT reported. The server
    // derives its error rate from sessions it has seen open, and this session
    // never sent a `start` — an `error` alone would be an event for a session
    // that does not exist there. It is the most interesting failure, so it is
    // logged here and belongs in crash reporting, which sees it either way.
    if (_startSent) {
      _emit(TelemetryEventType.error);
    } else {
      _log('fatal error before the first frame — session $_sessionId never '
          'opened server-side, not reported');
    }
    _sessionId = null;
    unawaited(flush());
  }

  // ── Player signals ────────────────────────────────────────────────────────

  /// The player reached its first frame / resumed playing.
  void onPlaying(Duration position) {
    if (!_sessionActive) return;
    _position = position;
    _lastWatchPosition ??= position;
    _playing = true;
    if (!_startSent) {
      _startup.stop();
      _startSent = true;
      _emit(TelemetryEventType.start, startupMs: _startup.elapsedMilliseconds);
      _progressTimer ??=
          Timer.periodic(config.progressInterval, (_) => _onProgressTick());
    }
  }

  void onPaused(Duration position) {
    if (!_sessionActive) return;
    _position = position;
    _lastWatchPosition = position;
    _playing = false;
    // A pause during a rebuffer still closes the stall — the freeze is over.
    _stopStallTimer();
  }

  /// Position update from the player (~every 300ms while playing).
  void onPosition(Duration position, {required bool playing}) {
    if (!_sessionActive) return;
    _position = position;
    if (!playing) {
      _lastWatchPosition = position;
      _playing = false;
      return;
    }
    _playing = true;
    final previous = _lastWatchPosition;
    _lastWatchPosition = position;
    if (previous == null) return;
    final advance = position - previous;
    // Backwards or a big jump forward is a seek: skip it, keep counting after.
    if (advance <= Duration.zero || advance > _seekThreshold) return;
    _watchedMs += advance.inMilliseconds;
  }

  /// Buffering began. Only counts as a stall once playback has started —
  /// buffering before the first frame is startup time.
  ///
  /// This is the only place the rebuffer counter moves: a freeze spanning
  /// several `progress` events is one stall, however long it lasts.
  void onBufferingStart() {
    if (!_sessionActive || !_startSent) return;
    if (_stallStartedAt != null) return; // already inside this stall
    _stallStartedAt = DateTime.now();
    _stallCount++;
  }

  /// Buffering ended.
  void onBufferingEnd() => _stopStallTimer();

  /// Height of the quality currently being rendered, e.g. 1080.
  void onResolution(int? height) {
    if (height == null || height <= 0) return;
    _resolution = '$height';
  }

  /// Closes an in-flight stall, banking the time it lasted. The count was
  /// already taken when the stall began.
  void _stopStallTimer() {
    final startedAt = _stallStartedAt;
    _stallStartedAt = null;
    if (startedAt == null) return;
    _stalledMs += DateTime.now().difference(startedAt).inMilliseconds;
  }

  void _onProgressTick() {
    if (!_sessionActive || !_startSent) return;
    // Nothing while paused or in the background, per the API contract.
    if (!_playing || !_foreground) return;
    _emit(TelemetryEventType.progress);
  }

  // ── Emission ──────────────────────────────────────────────────────────────

  /// Snapshots the pending deltas into an event, resets them to zero and
  /// queues it. Everything after the snapshot belongs to the next interval.
  void _emit(TelemetryEventType type, {int? startupMs}) {
    final sessionId = _sessionId;
    final contentId = _contentId;
    if (sessionId == null || contentId == null) return;

    final occurredAt = DateTime.now();
    final episodeId = _episodeId;
    final resolution = _resolution;
    final positionSeconds = _position.inSeconds;

    // `start` reports startup time with every delta at zero. Nothing is
    // consumed here on purpose: the bytes and buffering that happened while
    // opening the stream stay pending and are billed to the first `progress`,
    // so no traffic is silently dropped.
    if (type == TelemetryEventType.start) {
      _queueEvent(TelemetryEvent(
        type: type,
        sessionId: sessionId,
        occurredAt: occurredAt,
        contentId: contentId,
        episodeId: episodeId,
        positionSeconds: positionSeconds,
        secondsWatchedDelta: 0,
        bytesDownloadedDelta: config.bytesLoadedProvider == null ? null : 0,
        stallCountDelta: 0,
        stalledSecondsDelta: 0,
        startupMs: startupMs,
        resolution: resolution,
      ));
      return;
    }

    // An in-flight stall contributes the time elapsed so far; the remainder
    // lands in the next event. Its count was already taken at
    // onBufferingStart, so a long freeze spanning several events stays one
    // stall instead of being counted once per interval.
    final stallStartedAt = _stallStartedAt;
    final stallCount = _stallCount;
    var stalledMs = _stalledMs;
    if (stallStartedAt != null) {
      stalledMs += occurredAt.difference(stallStartedAt).inMilliseconds;
      _stallStartedAt = occurredAt;
    }

    final watchedSeconds = (_watchedMs ~/ 1000).clamp(0, 300);
    final stalledSeconds = (stalledMs ~/ 1000).clamp(0, 300);

    // Keep the sub-second remainders so 30s ticks don't systematically shave
    // a fraction of a second off every interval.
    _watchedMs -= watchedSeconds * 1000;
    _stalledMs = stalledMs - stalledSeconds * 1000;
    _stallCount = 0;

    _emitLock = _emitLock.then((_) async {
      final event = TelemetryEvent(
        type: type,
        sessionId: sessionId,
        occurredAt: occurredAt,
        contentId: contentId,
        episodeId: episodeId,
        positionSeconds: positionSeconds,
        secondsWatchedDelta: watchedSeconds,
        bytesDownloadedDelta: await _consumeBytesDelta(),
        stallCountDelta: stallCount,
        stalledSecondsDelta: stalledSeconds,
        startupMs: startupMs,
        resolution: resolution,
      );
      await _queue.add(event);
      _log('queued $event');
    });
  }

  /// Persists an event that needs no delta bookkeeping, keeping it in order
  /// behind anything already being emitted.
  void _queueEvent(TelemetryEvent event) {
    _emitLock = _emitLock.then((_) async {
      await _queue.add(event);
      _log('queued $event');
    });
  }

  /// Difference of the host-supplied cumulative byte counter since the last
  /// event. Null when no counter is wired — bytes are never estimated.
  Future<int?> _consumeBytesDelta() async {
    if (config.bytesLoadedProvider == null) return null;
    final total = await _readBytesTotal();
    if (total == null) return null;
    final baseline = _bytesBaselineReady ? (_bytesBaseline ?? 0) : total;
    _bytesBaseline = total;
    _bytesBaselineReady = true;
    final delta = total - baseline;
    // A counter that resets (new player instance) must not report negatives.
    return delta < 0 ? 0 : delta;
  }

  Future<int?> _readBytesTotal() async {
    final provider = config.bytesLoadedProvider;
    if (provider == null) return null;
    try {
      return await provider();
    } catch (e) {
      debugPrint('[MkPlayer] telemetry bytesLoadedProvider failed: $e');
      return null;
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
    // Let any event emitted a moment ago reach the queue first.
    await _emitLock;
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
      // No binding (pure Dart tests): foreground stays true.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        unawaited(flush());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _foreground = false;
      case AppLifecycleState.detached:
        // The app is going away: close the session and try one last delivery.
        _foreground = false;
        endSession();
    }
  }

  // ── Disposal ──────────────────────────────────────────────────────────────

  /// Emits the pending `end` event, flushes and releases everything.
  Future<void> close() async {
    if (_disposed || _closing) return;
    _closing = true;
    endSession();
    _progressTimer?.cancel();
    _flushTimer?.cancel();
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    await _emitLock;
    await flush(ignoreBackoff: true);
    _disposed = true;
    _client.close();
  }

  void _log(String message) {
    if (config.verbose) debugPrint('[MkPlayer] telemetry: $message');
  }

  // ── Session ids ───────────────────────────────────────────────────────────

  static final _random = Random();

  /// ULID-shaped id: 10 chars of timestamp + 16 random, Crockford base32 —
  /// 26 chars of `[0-9A-Z]`, inside what the API accepts, sortable by creation
  /// time and collision-free in practice.
  static String _generateSessionId() {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    var time = DateTime.now().millisecondsSinceEpoch;
    final chars = List<String>.filled(26, '0');
    for (var i = 9; i >= 0; i--) {
      chars[i] = alphabet[time & 0x1F];
      time >>= 5;
    }
    for (var i = 10; i < 26; i++) {
      chars[i] = alphabet[_random.nextInt(alphabet.length)];
    }
    return chars.join();
  }
}
