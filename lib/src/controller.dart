import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models/external_subtitle.dart';
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

// ─────────────────────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────────────────────

/// Core state and behaviour manager for a single player instance.
///
/// Create one instance per screen/route, pass it to [PlayerView], and dispose
/// it when the widget leaves the tree (e.g. in [State.dispose]).
class CustomPlayerController extends ChangeNotifier {
  // ── media_kit core ─────────────────────────────────────────────────────────

  late final Player _player;

  /// The [VideoController] bound to the [Video] widget inside [PlayerView].
  late final VideoController videoController;

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

  List<AudioTrack> _audioTracks = [];
  List<SubtitleTrack> _subtitleTracks = [];
  List<VideoTrack> _videoTracks = [];
  List<ExternalSubtitle> _externalSubtitles = const [];
  AudioTrack? _selectedAudioTrack;
  SubtitleTrack? _selectedSubtitleTrack;
  VideoTrack? _selectedVideoTrack;

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

  // True when the video's display aspect ratio is portrait (height > width).
  // Updated whenever the player emits new videoParams (e.g. after the first
  // decoded frame). Used by PlayerView to pick fullscreen orientations.
  bool _isPortraitVideo = false;
  bool get isPortraitVideo => _isPortraitVideo;

  // True once the first valid videoParams have been received (aspect > 0).
  // Used by PlayerView to know when auto-orientation can be safely applied.
  bool _videoParamsReceived = false;
  bool get videoParamsReceived => _videoParamsReceived;

  // ── Live ───────────────────────────────────────────────────────────────────

  // Set explicitly from PlayerSource.isLive — never auto-detected.
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
    _notify();
  }

  // ── Auto-retry ───────────────────────────────────────────────────────────────

  int _retryAttempt = 0;
  Timer? _retryTimer;

  /// Number of auto-retry attempts made for the current load (for UI hints).
  int get retryAttempt => _retryAttempt;

  // ── Internal ───────────────────────────────────────────────────────────────

  final List<StreamSubscription<dynamic>> _subs = [];
  bool _disposed = false;
  PlayerSource? _lastSource;
  Timer? _loadingTimeout;

  // startAt: consumed on first playing event
  Duration? _pendingStartAt;

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

  double get progress =>
      _duration.inMilliseconds > 0
          ? (_position.inMilliseconds / _duration.inMilliseconds)
              .clamp(0.0, 1.0)
          : 0.0;

  // Sentinel tracks ('auto'/'no') that media_kit always includes are filtered
  // out so consumers only see real, selectable tracks.
  List<AudioTrack> get audioTracks =>
      _audioTracks.where(_isRealTrackId).toList();
  List<SubtitleTrack> get subtitleTracks =>
      _subtitleTracks.where(_isRealTrackId).toList();
  List<VideoTrack> get videoTracks =>
      _videoTracks.where(_isRealTrackId).toList();
  AudioTrack? get selectedAudioTrack => _selectedAudioTrack;
  SubtitleTrack? get selectedSubtitleTrack => _selectedSubtitleTrack;
  VideoTrack? get selectedVideoTrack => _selectedVideoTrack;

  /// External subtitles supplied via [PlayerSource.externalSubtitles].
  List<ExternalSubtitle> get externalSubtitles =>
      List.unmodifiable(_externalSubtitles);

  static bool _isRealTrackId(dynamic t) => t.id != 'auto' && t.id != 'no';

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
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: config.bufferSize,
        logLevel: MPVLogLevel.warn,
      ),
    );
    videoController = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: config.enableHardwareAcceleration,
      ),
    );
    _player.setVolume(_volume * 100);
    _player.setRate(_speed);
    _attachListeners();
  }

  void _attachListeners() {
    _subs.addAll([
      _player.stream.playing.listen(_handlePlaying),
      _player.stream.buffering.listen(_handleBuffering),
      _player.stream.position.listen(_handlePosition),
      _player.stream.duration.listen(_handleDuration),
      _player.stream.buffer.listen(_handleBuffer),
      _player.stream.volume.listen(_handleVolume),
      _player.stream.rate.listen(_handleRate),
      _player.stream.tracks.listen(_handleTracks),
      _player.stream.track.listen(_handleTrack),
      _player.stream.completed.listen(_handleCompleted),
      _player.stream.error.listen(_handleError),
      _player.stream.videoParams.listen(_handleVideoParams),
    ]);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> open(PlayerSource source) async {
    if (_disposed) return;
    // New, explicit open → reset the auto-retry counter.
    _retryAttempt = 0;
    _retryTimer?.cancel();
    await _load(source);
  }

  // Core load routine, shared by open() and auto-retry. Does NOT reset the
  // retry counter, so backoff persists across attempts.
  Future<void> _load(PlayerSource source) async {
    if (_disposed) return;
    _beginSource(source);
    try {
      final media = Media(source.uri, httpHeaders: source.headers);
      await _player.open(media, play: config.autoPlay);
    } catch (e, st) {
      debugPrint('[MkPlayer] open() error: $e\n$st');
      _onError('Unable to open source: $e');
    }
  }

  Future<void> openPlaylist(List<PlayerSource> sources) async {
    if (_disposed || sources.isEmpty) return;
    _retryAttempt = 0;
    _retryTimer?.cancel();
    _beginSource(sources.first);
    try {
      final playlist = Playlist(
        sources.map((s) => Media(s.uri, httpHeaders: s.headers)).toList(),
      );
      await _player.open(playlist, play: config.autoPlay);
    } catch (e, st) {
      debugPrint('[MkPlayer] openPlaylist() error: $e\n$st');
      _onError('Unable to open playlist: $e');
    }
  }

  // Resets per-source state and enters the loading phase. Shared by single and
  // playlist loads. Storyboard fetch is kicked off in the background.
  void _beginSource(PlayerSource source) {
    _lastSource = source;
    _currentTitle = source.title;
    _storyboard = null;
    _isLive = source.isLive;
    _videoParamsReceived = false;
    _pendingStartAt = source.startAt;
    _externalSubtitles = source.externalSubtitles;
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
    await _player.play();
  }

  Future<void> pause() async {
    if (_disposed) return;
    await _player.pause();
  }

  Future<void> togglePlayPause() async {
    if (_disposed) return;
    await _player.playOrPause();
  }

  /// Seeks to [position], clamped to the valid `[0, duration]` range.
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    await _player.seek(_clampPosition(position));
  }

  Duration _clampPosition(Duration p) {
    if (p < Duration.zero) return Duration.zero;
    if (_duration > Duration.zero && p > _duration) return _duration;
    return p;
  }

  Future<void> setVolume(double value) async {
    if (_disposed) return;
    _volume = value.clamp(0.0, 1.0);
    if (!_muted) await _player.setVolume(_volume * 100);
    _notify();
  }

  Future<void> toggleMute() async {
    if (_disposed) return;
    _muted = !_muted;
    await _player.setVolume(_muted ? 0 : _volume * 100);
    _notify();
  }

  Future<void> setSpeed(double value) async {
    if (_disposed) return;
    _speed = value.clamp(0.25, 4.0);
    await _player.setRate(_speed);
    _notify();
  }

  Future<void> setAudioTrack(AudioTrack track) async {
    if (_disposed) return;
    await _player.setAudioTrack(track);
    _selectedAudioTrack = track;
    _notify();
  }

  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    if (_disposed) return;
    await _player.setSubtitleTrack(track);
    _selectedSubtitleTrack = track;
    _notify();
  }

  Future<void> disableSubtitles() async {
    if (_disposed) return;
    await _player.setSubtitleTrack(SubtitleTrack.no());
    _selectedSubtitleTrack = SubtitleTrack.no();
    _notify();
  }

  /// Loads and displays an external subtitle from [PlayerSource.externalSubtitles].
  Future<void> setExternalSubtitle(ExternalSubtitle sub) async {
    if (_disposed) return;
    final track = SubtitleTrack.uri(
      sub.uri,
      title: sub.title,
      language: sub.language,
    );
    await _player.setSubtitleTrack(track);
    _selectedSubtitleTrack = track;
    _notify();
  }

  /// Whether [sub] is the currently active subtitle track.
  bool isExternalSubtitleSelected(ExternalSubtitle sub) =>
      (_selectedSubtitleTrack?.uri ?? false) &&
      _selectedSubtitleTrack?.id == sub.uri;

  Future<void> setVideoTrack(VideoTrack track) async {
    if (_disposed) return;
    await _player.setVideoTrack(track);
    _selectedVideoTrack = track;
    _notify();
  }

  /// Manually retries the last source (e.g. from the error overlay button).
  /// Resets the auto-retry counter.
  Future<void> retry() async {
    if (_disposed || _lastSource == null) return;
    _retryAttempt = 0;
    _retryTimer?.cancel();
    _errorMessage = null;
    await _load(_lastSource!);
  }

  // ── startAt ────────────────────────────────────────────────────────────────

  void _applyStartAt() {
    final t = _pendingStartAt;
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

  // ── Stream handlers ────────────────────────────────────────────────────────

  void _handlePlaying(bool playing) {
    if (_disposed) return;
    if (playing) {
      _loadingTimeout?.cancel();
      _retryAttempt = 0; // successful playback clears the retry counter
      _applyStartAt(); // seek to startAt before first UI notification
      _transition(MkPlayerState.playing);
      _setWakelock(true);
    } else {
      if (_state == MkPlayerState.playing ||
          _state == MkPlayerState.buffering) {
        _transition(MkPlayerState.paused);
      }
      _setWakelock(false);
    }
    _notify();
  }

  void _handleBuffering(bool buffering) {
    if (_disposed) return;
    if (buffering) {
      if (_state != MkPlayerState.error) {
        _transition(MkPlayerState.buffering);
        _notify();
      }
    } else if (_state == MkPlayerState.buffering ||
        _state == MkPlayerState.loading) {
      _transition(
        _player.state.playing ? MkPlayerState.playing : MkPlayerState.paused,
      );
      _notify();
    }
  }

  void _handlePosition(Duration pos) {
    if (_disposed) return;
    _position = pos;
    if (_posterVisible && pos > Duration.zero) _posterVisible = false;
    _notify();
    _maybeFirePositionCallback(pos);
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

  void _handleDuration(Duration dur) {
    if (_disposed) return;
    _duration = dur;
    _notify();
  }

  void _handleBuffer(Duration buf) {
    if (_disposed) return;
    _buffered = buf;
    _notify();
  }

  void _handleVolume(double vol) {
    if (_disposed) return;
    if (!_muted) _volume = (vol / 100).clamp(0.0, 1.0);
    _notify();
  }

  void _handleRate(double rate) {
    if (_disposed) return;
    _speed = rate;
    _notify();
  }

  void _handleTracks(Tracks tracks) {
    if (_disposed) return;
    _audioTracks = tracks.audio;
    _subtitleTracks = tracks.subtitle;
    _videoTracks = tracks.video;
    _notify();
  }

  void _handleTrack(Track track) {
    if (_disposed) return;
    _selectedAudioTrack = track.audio;
    _selectedSubtitleTrack = track.subtitle;
    _selectedVideoTrack = track.video;
    _notify();
  }

  void _handleCompleted(bool completed) {
    if (_disposed || !completed) return;
    if (config.loop) {
      _player.seek(Duration.zero).then((_) => _player.play());
    } else {
      _transition(MkPlayerState.completed);
      _setWakelock(false);
      _notify();
      config.onCompleted?.call();
    }
  }

  void _handleVideoParams(VideoParams params) {
    if (_disposed) return;
    final aspect = params.aspect;
    if (aspect != null && aspect > 0) {
      _isPortraitVideo = aspect < 1.0;
      _videoParamsReceived = true;
    }
    _notify();
  }

  void _handleError(String error) {
    if (_disposed) return;
    _onError(error);
  }

  void _onError(String message) {
    _loadingTimeout?.cancel();
    _setWakelock(false);

    // Attempt an automatic retry with exponential backoff before surfacing
    // the error overlay.
    if (_lastSource != null && _retryAttempt < config.autoRetryMaxAttempts) {
      _retryAttempt++;
      final base = config.autoRetryBaseDelay.inMilliseconds;
      final backoffMs =
          (base * (1 << (_retryAttempt - 1))).clamp(base, 30000);
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
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    WakelockPlus.disable().ignore();
    _player.dispose();
    super.dispose();
  }
}
