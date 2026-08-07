import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'playback_event.dart';

/// Receives every [PlaybackEvent] a [PlaybackSessionTracker] measures.
///
/// Sinks are called in the order they were registered, once per event, with
/// the very same instance — a sink must not mutate what it receives.
typedef PlaybackEventSink = void Function(PlaybackEvent event);

/// The few measurement knobs the tracker needs.
///
/// Nothing here has to do with delivery. When telemetry reporting is
/// configured, `TelemetryConfig.playbackOptions` derives these from it instead
/// of restating the values.
class PlaybackSessionOptions {
  const PlaybackSessionOptions({
    this.progressInterval = const Duration(seconds: 30),
    this.bytesLoadedProvider,
    this.verbose = false,
  });

  /// How often a `progress` event is emitted while actually playing.
  final Duration progressInterval;

  /// Cumulative bytes loaded from the network, if the host can report them.
  /// Null leaves [PlaybackEvent.bytesDownloadedDelta] unset on every event —
  /// traffic is never estimated from the bitrate.
  final FutureOr<int?> Function()? bytesLoadedProvider;

  /// Log every emitted event with `debugPrint`.
  final bool verbose;
}

/// Measures one playback session and emits `start` / `progress` / `end` /
/// `error` to its sinks. Pure measurement: no queue, no network, no disk.
///
/// It owns the rules a consumer depends on:
///
/// * every counter is a **delta since the previous event** and is reset to zero
///   once the event is emitted — a lost report costs one interval, nothing more;
/// * `occurredAt` always carries a UTC offset, so a report delivered the next
///   day is still filed under the day it was watched;
/// * a fresh `sessionId` per media load — repeats of the same title included —
///   repeated on every event of that playback;
/// * `progress` only ticks while the video is actually playing in the
///   foreground — never while paused or backgrounded.
///
/// Nothing is measured for a source without a `contentId`: [beginSession] is
/// simply never called for it, so no sink sees an event for that playback.
///
/// `CustomPlayerController` creates exactly one per player, as soon as
/// `PlayerConfig.telemetry` is enabled or `PlayerConfig.onPlaybackEvent` is
/// set. `TelemetryReporter` and `onPlaybackEvent` are then two sinks of that
/// single tracker, so both see the exact same event exactly once.
class PlaybackSessionTracker with WidgetsBindingObserver {
  PlaybackSessionTracker({
    this.options = const PlaybackSessionOptions(),
    Iterable<PlaybackEventSink> sinks = const [],
  }) : _sinks = List.of(sinks) {
    _observeLifecycle();
  }

  final PlaybackSessionOptions options;
  final List<PlaybackEventSink> _sinks;

  /// Position jumps larger than this are treated as seeks and never counted as
  /// watched time (positions arrive roughly every 300ms while playing).
  static const _seekThreshold = Duration(seconds: 5);

  /// Ceiling for the seconds a single event may carry. It paces the deltas —
  /// a device whose clock jumped, or a report delayed for minutes, spreads the
  /// time over the following events instead of putting an implausible figure
  /// in one. Nothing is lost: the excess stays pending.
  static const _maxDeltaSeconds = 300;

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

  /// Set once [dispose] has run; nothing is measured afterwards.
  bool _disposed = false;

  // Keeps emitted events in chronological order despite async byte reads.
  Future<void> _emitLock = Future.value();

  /// Whether a playback session is currently being measured.
  bool get sessionActive => _sessionActive;

  /// Id of the session being measured, for diagnostics. Null between sessions.
  String? get sessionId => _sessionId;

  /// Completes once every event emitted so far has reached the sinks.
  ///
  /// A consumer that needs to act on the full picture (draining a queue, for
  /// instance) awaits this first: an event whose byte delta is still being read
  /// has not been dispatched yet.
  Future<void> get settled => _emitLock;

  // ── Sinks ─────────────────────────────────────────────────────────────────

  /// Registers [sink]. Adding the same sink twice is a no-op, so an event is
  /// never delivered to it more than once.
  void addSink(PlaybackEventSink sink) {
    if (_sinks.contains(sink)) return;
    _sinks.add(sink);
  }

  void removeSink(PlaybackEventSink sink) => _sinks.remove(sink);

  // ── Session lifecycle ─────────────────────────────────────────────────────

  /// Starts measuring a new playback session — one per media load, repeats of
  /// the same media included.
  void beginSession({required int contentId, int? episodeId}) {
    if (_disposed) return;
    if (contentId < 1) {
      // An event nobody can attribute is worse than no event: consumers key
      // their reports on this id, so a session without a real one is dropped.
      debugPrint('[MkPlayer] playback: ignoring session with contentId '
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

  /// Ends the current session, emitting the deltas that are still pending.
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
    // is nothing to close on the consumer side.
    if (wasStarted) _emit(PlaybackEventType.end);
    _sessionId = null;
  }

  /// A fatal player error: closes the session with the pending deltas. The
  /// error detail deliberately never leaves this layer — that belongs in crash
  /// reporting.
  void reportError() {
    if (!_sessionActive) return;
    _stopStallTimer();
    _sessionActive = false;
    _playing = false;
    _progressTimer?.cancel();
    _progressTimer = null;
    _startup.stop();
    // Deliberate: a failure before the first frame is NOT reported. A consumer
    // derives its error rate from sessions it has seen open, and this session
    // never sent a `start` — an `error` alone would be an event for a session
    // that does not exist there. It is the most interesting failure, so it is
    // logged here and belongs in crash reporting, which sees it either way.
    if (_startSent) {
      _emit(PlaybackEventType.error);
    } else {
      _log('fatal error before the first frame — session $_sessionId never '
          'opened, not reported');
    }
    _sessionId = null;
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
      _emit(PlaybackEventType.start, startupMs: _startup.elapsedMilliseconds);
      _progressTimer ??=
          Timer.periodic(options.progressInterval, (_) => _onProgressTick());
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
    _emit(PlaybackEventType.progress);
  }

  // ── Emission ──────────────────────────────────────────────────────────────

  /// Snapshots the pending deltas into an event, resets them to zero and
  /// dispatches it. Everything after the snapshot belongs to the next interval.
  void _emit(PlaybackEventType type, {int? startupMs}) {
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
    if (type == PlaybackEventType.start) {
      _dispatchInOrder(PlaybackEvent(
        type: type,
        sessionId: sessionId,
        occurredAt: occurredAt,
        contentId: contentId,
        episodeId: episodeId,
        positionSeconds: positionSeconds,
        secondsWatchedDelta: 0,
        bytesDownloadedDelta: options.bytesLoadedProvider == null ? null : 0,
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

    final watchedSeconds = (_watchedMs ~/ 1000).clamp(0, _maxDeltaSeconds);
    final stalledSeconds = (stalledMs ~/ 1000).clamp(0, _maxDeltaSeconds);

    // Keep the sub-second remainders so 30s ticks don't systematically shave
    // a fraction of a second off every interval. Whatever the ceiling above
    // held back stays pending too and rides on the next event — the cap paces
    // the deltas, it never discards measured time.
    _watchedMs -= watchedSeconds * 1000;
    _stalledMs = stalledMs - stalledSeconds * 1000;
    _stallCount = 0;

    _emitLock = _emitLock.then((_) async {
      _dispatch(PlaybackEvent(
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
      ));
    });
  }

  /// Dispatches an event that needs no delta bookkeeping, keeping it behind
  /// anything already being emitted.
  void _dispatchInOrder(PlaybackEvent event) {
    _emitLock = _emitLock.then((_) => _dispatch(event));
  }

  /// Hands one event to every sink. A sink that throws is logged and skipped:
  /// the callback belongs to the host app, and its failure must not take down
  /// playback or starve the other sinks.
  void _dispatch(PlaybackEvent event) {
    for (final sink in List.of(_sinks)) {
      try {
        sink(event);
      } catch (e) {
        debugPrint('[MkPlayer] playback event sink failed: $e');
      }
    }
    _log('emitted $event');
  }

  /// Difference of the host-supplied cumulative byte counter since the last
  /// event. Null when no counter is wired — bytes are never estimated.
  Future<int?> _consumeBytesDelta() async {
    if (options.bytesLoadedProvider == null) return null;
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
    final provider = options.bytesLoadedProvider;
    if (provider == null) return null;
    try {
      return await provider();
    } catch (e) {
      debugPrint('[MkPlayer] playback bytesLoadedProvider failed: $e');
      return null;
    }
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
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _foreground = false;
      case AppLifecycleState.detached:
        // The app is going away: close the session while it can still be
        // reported.
        _foreground = false;
        endSession();
    }
  }

  // ── Disposal ──────────────────────────────────────────────────────────────

  /// Emits the pending `end` event and stops measuring. Events already
  /// scheduled still reach the sinks — await [settled] to be sure they have.
  void dispose() {
    if (_disposed) return;
    endSession();
    _disposed = true;
    _progressTimer?.cancel();
    _progressTimer = null;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }

  void _log(String message) {
    if (options.verbose) debugPrint('[MkPlayer] playback: $message');
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
