import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models/player_config.dart';
import 'models/player_source.dart';
import 'models/storyboard.dart';
import 'models/video_fit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public types
// ─────────────────────────────────────────────────────────────────────────────

enum MkPlayerState {
  idle,
  loading,
  playing,
  paused,
  buffering,
  completed,
  error,
}

BoxFit _boxFitOf(VideoFit fit) => switch (fit) {
      VideoFit.contain => BoxFit.contain,
      VideoFit.cover => BoxFit.cover,
      VideoFit.fill => BoxFit.fill,
    };

// ─────────────────────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────────────────────

/// Core state and behaviour manager for a single player instance.
///
/// Create one instance per screen/route, pass it to [PlayerView], and dispose
/// it when the widget leaves the tree (e.g. in [State.dispose]).
///
/// Backed by `better_player_plus` (ExoPlayer on Android).
class CustomPlayerController extends ChangeNotifier {
  // ── better_player core ───────────────────────────────────────────────────

  /// The underlying controller bound to the [BetterPlayer] widget in [PlayerView].
  late final BetterPlayerController betterPlayerController;

  // ── Configuration ──────────────────────────────────────────────────────────

  final PlayerConfig config;

  // ── Observable state ───────────────────────────────────────────────────────

  MkPlayerState _state = MkPlayerState.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  double _volume;
  bool _muted = false;
  double _speed;
  String? _errorMessage;

  // ── Storyboard & metadata ──────────────────────────────────────────────────

  Storyboard? _storyboard;
  String? _currentTitle;
  String? _currentPosterUrl;
  bool _posterVisible = false;

  Storyboard? get storyboard => _storyboard;
  String? get currentTitle => _currentTitle;
  String? get currentPosterUrl => _currentPosterUrl;
  bool get posterVisible => _posterVisible;

  // ── Video orientation ──────────────────────────────────────────────────────

  bool _isPortraitVideo = false;
  bool get isPortraitVideo => _isPortraitVideo;

  bool _videoParamsReceived = false;
  bool get videoParamsReceived => _videoParamsReceived;

  // ── Live ───────────────────────────────────────────────────────────────────

  bool _isLive = false;
  bool get isLive => _isLive;

  // ── Video fit ──────────────────────────────────────────────────────────────

  late VideoFit _videoFit = config.initialVideoFit;
  VideoFit get videoFit => _videoFit;

  /// Cycles contain → cover → fill → contain.
  void cycleVideoFit() {
    const order = [VideoFit.contain, VideoFit.cover, VideoFit.fill];
    final next = order[(order.indexOf(_videoFit) + 1) % order.length];
    setVideoFit(next);
  }

  void setVideoFit(VideoFit fit) {
    if (_disposed || _videoFit == fit) return;
    _videoFit = fit;
    betterPlayerController.setOverriddenFit(_boxFitOf(fit));
    _notify();
  }

  // ── Auto-retry ───────────────────────────────────────────────────────────────

  int _retryAttempt = 0;
  Timer? _retryTimer;

  /// Number of auto-retry attempts made for the current load (for UI hints).
  int get retryAttempt => _retryAttempt;

  // ── Internal ───────────────────────────────────────────────────────────────

  bool _disposed = false;
  PlayerSource? _lastSource;
  Timer? _loadingTimeout;

  // startAt: consumed once playback is initialised
  Duration? _pendingStartAt;
  bool _startAtApplied = false;

  // onPositionChanged throttle
  DateTime? _lastPositionCallback;

  // ── Getters ────────────────────────────────────────────────────────────────

  MkPlayerState get state => _state;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get buffered => _buffered;
  double get volume => _muted ? 0.0 : _volume;
  double get rawVolume => _volume;
  bool get muted => _muted;
  double get speed => _speed;
  String? get errorMessage => _errorMessage;

  bool get isIdle => _state == MkPlayerState.idle;
  bool get isLoading => _state == MkPlayerState.loading;
  bool get isPlaying => _state == MkPlayerState.playing;
  bool get isPaused => _state == MkPlayerState.paused;
  bool get isBuffering => _state == MkPlayerState.buffering;
  bool get isCompleted => _state == MkPlayerState.completed;
  bool get hasError => _state == MkPlayerState.error;

  Duration get remaining =>
      _duration > _position ? _duration - _position : Duration.zero;

  double get progress => _duration.inMilliseconds > 0
      ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  // ── Tracks (HLS/DASH ASMS) ───────────────────────────────────────────────────

  /// Selectable audio tracks parsed from the HLS/DASH manifest.
  List<BetterPlayerAsmsAudioTrack> get audioTracks =>
      betterPlayerController.betterPlayerAsmsAudioTracks ?? const [];
  BetterPlayerAsmsAudioTrack? get selectedAudioTrack =>
      betterPlayerController.betterPlayerAsmsAudioTrack;

  /// Selectable video-quality tracks parsed from the HLS/DASH manifest.
  List<BetterPlayerAsmsTrack> get videoTracks =>
      betterPlayerController.betterPlayerAsmsTracks;
  BetterPlayerAsmsTrack? get selectedVideoTrack =>
      betterPlayerController.betterPlayerAsmsTrack;

  /// Subtitle sources: embedded (HLS/DASH), external (supplied via
  /// [PlayerSource.externalSubtitles]) and an "off" entry — all unified by
  /// better_player into a single list.
  List<BetterPlayerSubtitlesSource> get subtitleSources =>
      betterPlayerController.betterPlayerSubtitlesSourceList;
  BetterPlayerSubtitlesSource? get selectedSubtitle =>
      betterPlayerController.betterPlayerSubtitlesSource;

  /// Whether there is at least one real (non-"off") subtitle to choose from.
  bool get hasSubtitles => subtitleSources
      .any((s) => s.type != BetterPlayerSubtitlesSourceType.none);

  // ── PiP ────────────────────────────────────────────────────────────────────

  bool _pipActive = false;
  bool get pipActive => _pipActive;

  void notifyPipEntered() {
    _pipActive = true;
    _notify();
  }

  void notifyPipExited() {
    _pipActive = false;
    _notify();
  }

  // ── Constructor ────────────────────────────────────────────────────────────

  CustomPlayerController({PlayerConfig? config})
      : config = config ?? const PlayerConfig(),
        _volume = config?.initialVolume ?? 1.0,
        _speed = config?.initialSpeed ?? 1.0 {
    _initPlayer();
  }

  void _initPlayer() {
    betterPlayerController = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: config.autoPlay,
        looping: config.loop,
        fit: _boxFitOf(config.initialVideoFit),
        // We render our own controls overlay and manage fullscreen ourselves.
        controlsConfiguration:
            const BetterPlayerControlsConfiguration(showControls: false),
        handleLifecycle: false,
        autoDispose: false,
        expandToFill: true,
      ),
    );
    betterPlayerController.addEventsListener(_onEvent);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> open(PlayerSource source) async {
    if (_disposed) return;
    _retryAttempt = 0;
    _retryTimer?.cancel();
    await _load(source);
  }

  Future<void> _load(PlayerSource source) async {
    if (_disposed) return;
    _beginSource(source);
    try {
      await betterPlayerController.setupDataSource(_buildDataSource(source));
    } catch (e, st) {
      debugPrint('[MkPlayer] setupDataSource error: $e\n$st');
      _onError('Unable to open source: $e');
    }
  }

  /// Opening a playlist is not supported by the better_player backend in this
  /// package; the first source is played. Kept for API compatibility.
  Future<void> openPlaylist(List<PlayerSource> sources) async {
    if (_disposed || sources.isEmpty) return;
    await open(sources.first);
  }

  BetterPlayerDataSource _buildDataSource(PlayerSource source) {
    final subtitles = source.externalSubtitles
        .map(
          (s) => BetterPlayerSubtitlesSource(
            type: BetterPlayerSubtitlesSourceType.network,
            name: s.title ?? s.language?.toUpperCase() ?? 'Subtitle',
            urls: [s.uri],
          ),
        )
        .toList();

    final buffering = BetterPlayerBufferingConfiguration(
      minBufferMs: config.minBufferMs,
      maxBufferMs: config.maxBufferMs,
      bufferForPlaybackMs: config.bufferForPlaybackMs,
      bufferForPlaybackAfterRebufferMs: config.bufferForPlaybackAfterRebufferMs,
    );

    return BetterPlayerDataSource(
      source.isLocal
          ? BetterPlayerDataSourceType.file
          : BetterPlayerDataSourceType.network,
      source.isLocal ? source.path! : source.url!,
      headers: source.headers.isEmpty ? null : source.headers,
      subtitles: subtitles.isEmpty ? null : subtitles,
      liveStream: source.isLive,
      bufferingConfiguration: buffering,
    );
  }

  // Resets per-source state and enters the loading phase. Storyboard fetch is
  // kicked off in the background.
  void _beginSource(PlayerSource source) {
    _lastSource = source;
    _currentTitle = source.title;
    _storyboard = null;
    _isLive = source.isLive;
    _videoParamsReceived = false;
    _pendingStartAt = source.startAt;
    _startAtApplied = false;
    _currentPosterUrl = source.posterUrl;
    _posterVisible = _currentPosterUrl != null;

    _transition(MkPlayerState.loading);
    _notify();
    _startLoadingTimeout();

    if (source.storyboardUrl != null) {
      _loadStoryboard(source.storyboardUrl!, source.storyboardHeaders);
    }
  }

  Future<void> play() async {
    if (_disposed) return;
    await betterPlayerController.play();
  }

  Future<void> pause() async {
    if (_disposed) return;
    await betterPlayerController.pause();
  }

  Future<void> togglePlayPause() async {
    if (_disposed) return;
    if (betterPlayerController.isPlaying() ?? false) {
      await betterPlayerController.pause();
    } else {
      await betterPlayerController.play();
    }
  }

  /// Seeks to [position], clamped to the valid `[0, duration]` range.
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    await betterPlayerController.seekTo(_clampPosition(position));
  }

  Duration _clampPosition(Duration p) {
    if (p < Duration.zero) return Duration.zero;
    if (_duration > Duration.zero && p > _duration) return _duration;
    return p;
  }

  Future<void> setVolume(double value) async {
    if (_disposed) return;
    _volume = value.clamp(0.0, 1.0);
    if (!_muted) await betterPlayerController.setVolume(_volume);
    _notify();
  }

  Future<void> toggleMute() async {
    if (_disposed) return;
    _muted = !_muted;
    await betterPlayerController.setVolume(_muted ? 0 : _volume);
    _notify();
  }

  Future<void> setSpeed(double value) async {
    if (_disposed) return;
    _speed = value.clamp(0.25, 4.0);
    await betterPlayerController.setSpeed(_speed);
    _notify();
  }

  // ── Track selection ──────────────────────────────────────────────────────

  void setAudioTrack(BetterPlayerAsmsAudioTrack track) {
    if (_disposed) return;
    betterPlayerController.setAudioTrack(track);
    _notify();
  }

  void setVideoTrack(BetterPlayerAsmsTrack track) {
    if (_disposed) return;
    betterPlayerController.setTrack(track);
    _notify();
  }

  Future<void> setSubtitle(BetterPlayerSubtitlesSource source) async {
    if (_disposed) return;
    await betterPlayerController.setupSubtitleSource(source);
    _notify();
  }

  /// Disables subtitles by selecting the "off" source, if present.
  Future<void> disableSubtitles() async {
    if (_disposed) return;
    final off = subtitleSources.firstWhere(
      (s) => s.type == BetterPlayerSubtitlesSourceType.none,
      orElse: () => BetterPlayerSubtitlesSource(
        type: BetterPlayerSubtitlesSourceType.none,
      ),
    );
    await setSubtitle(off);
  }

  /// Manually retries the last source (e.g. from the error overlay button).
  Future<void> retry() async {
    if (_disposed || _lastSource == null) return;
    _retryAttempt = 0;
    _retryTimer?.cancel();
    _errorMessage = null;
    await _load(_lastSource!);
  }

  // ── startAt ────────────────────────────────────────────────────────────────

  void _applyStartAt() {
    if (_startAtApplied) return;
    final t = _pendingStartAt;
    _startAtApplied = true;
    _pendingStartAt = null;
    if (t == null || t <= Duration.zero) return;
    seek(t); // seek() clamps to the valid range
  }

  // ── Storyboard ─────────────────────────────────────────────────────────────

  Future<void> _loadStoryboard(String url, Map<String, String> headers) async {
    final board = await Storyboard.load(url, headers: headers);
    if (_disposed) return;
    _storyboard = board;
    _notify();
  }

  // ── Loading timeout ────────────────────────────────────────────────────────

  void _startLoadingTimeout() {
    _loadingTimeout?.cancel();
    if (config.loadingTimeoutSeconds <= 0) return;
    _loadingTimeout = Timer(
      Duration(seconds: config.loadingTimeoutSeconds),
      () {
        if (_disposed) return;
        if (_state == MkPlayerState.loading ||
            _state == MkPlayerState.buffering) {
          _onError(
            'Stream timed out. Check the URL and your network connection.',
          );
        }
      },
    );
  }

  // ── Event handling ───────────────────────────────────────────────────────

  void _onEvent(BetterPlayerEvent event) {
    if (_disposed) return;
    final value = betterPlayerController.videoPlayerController?.value;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        _loadingTimeout?.cancel();
        _retryAttempt = 0;
        betterPlayerController.setVolume(_muted ? 0 : _volume);
        betterPlayerController.setSpeed(_speed);
        _readVideoParams(value);
        _syncFromValue(value);
        _applyStartAt();
        if (!(betterPlayerController.isPlaying() ?? false)) {
          _transition(MkPlayerState.paused);
        }
      case BetterPlayerEventType.play:
        _loadingTimeout?.cancel();
        _transition(MkPlayerState.playing);
        _setWakelock(true);
      case BetterPlayerEventType.pause:
        if (_state != MkPlayerState.completed) {
          _transition(MkPlayerState.paused);
        }
        _setWakelock(false);
      case BetterPlayerEventType.progress:
        _syncFromValue(value);
        _readVideoParams(value);
      case BetterPlayerEventType.bufferingStart:
        if (_state != MkPlayerState.error) {
          _transition(MkPlayerState.buffering);
        }
      case BetterPlayerEventType.bufferingEnd:
        if (_state == MkPlayerState.buffering ||
            _state == MkPlayerState.loading) {
          _transition(
            (betterPlayerController.isPlaying() ?? false)
                ? MkPlayerState.playing
                : MkPlayerState.paused,
          );
        }
      case BetterPlayerEventType.bufferingUpdate:
        _syncFromValue(value);
      case BetterPlayerEventType.finished:
        _handleCompleted();
      case BetterPlayerEventType.exception:
        _onError(event.parameters?['exception']?.toString() ??
            value?.errorDescription ??
            'Playback error');
      case BetterPlayerEventType.setSpeed:
      case BetterPlayerEventType.setVolume:
        _syncFromValue(value);
      default:
        break;
    }
    _notify();
  }

  void _syncFromValue(VideoPlayerValue? v) {
    if (v == null) return;
    _position = v.position;
    _duration = v.duration ?? Duration.zero;
    // buffered is a list of ranges; surface the furthest buffered point.
    var bufferedEnd = Duration.zero;
    for (final range in v.buffered) {
      if (range.end > bufferedEnd) bufferedEnd = range.end;
    }
    _buffered = bufferedEnd;
    if (_posterVisible && v.position > Duration.zero) _posterVisible = false;
    _maybeFirePositionCallback(_position);
  }

  void _readVideoParams(VideoPlayerValue? v) {
    final size = v?.size;
    if (size != null && size.width > 0 && size.height > 0) {
      _isPortraitVideo = size.height > size.width;
      _videoParamsReceived = true;
    }
  }

  void _maybeFirePositionCallback(Duration pos) {
    final cb = config.onPositionChanged;
    if (cb == null) return;
    final now = DateTime.now();
    final last = _lastPositionCallback;
    if (last == null || now.difference(last).inMilliseconds >= 1000) {
      _lastPositionCallback = now;
      cb(pos);
    }
  }

  void _handleCompleted() {
    if (_disposed) return;
    if (config.loop) return; // better_player handles looping itself
    _transition(MkPlayerState.completed);
    _setWakelock(false);
    config.onCompleted?.call();
  }

  void _onError(String message) {
    _loadingTimeout?.cancel();
    _setWakelock(false);

    // Automatic retry with exponential backoff before surfacing the overlay.
    if (_lastSource != null && _retryAttempt < config.autoRetryMaxAttempts) {
      _retryAttempt++;
      final base = config.autoRetryBaseDelay.inMilliseconds;
      final backoffMs = (base * (1 << (_retryAttempt - 1))).clamp(base, 30000);
      debugPrint(
        '[MkPlayer] auto-retry $_retryAttempt/${config.autoRetryMaxAttempts} '
        'in ${backoffMs}ms — $message',
      );
      _transition(MkPlayerState.loading);
      _notify();
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(milliseconds: backoffMs), () {
        if (!_disposed && _lastSource != null) _load(_lastSource!);
      });
      return;
    }

    _errorMessage = message;
    _transition(MkPlayerState.error);
    _notify();
    config.onError?.call(message);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _transition(MkPlayerState next) {
    if (_state == next) return;
    _state = next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setWakelock(bool enable) {
    if (!config.useWakelock) return;
    if (enable) {
      WakelockPlus.enable().ignore();
    } else {
      WakelockPlus.disable().ignore();
    }
  }

  // ── Disposal ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadingTimeout?.cancel();
    _retryTimer?.cancel();
    betterPlayerController.removeEventsListener(_onEvent);
    WakelockPlus.disable().ignore();
    betterPlayerController.dispose(forceDispose: true);
    super.dispose();
  }
}
