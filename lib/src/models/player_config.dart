import 'package:better_player_plus/better_player_plus.dart'
    show BetterPlayerSubtitlesConfiguration;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../telemetry/telemetry_config.dart';
import 'player_action.dart';
import 'video_fit.dart';

/// Immutable configuration for [CustomPlayerController] and [PlayerView].
///
/// Pass a [PlayerConfig] to [CustomPlayerController] at construction time.
/// All fields are optional — the defaults produce a sensible, production-ready
/// player experience without any configuration.
class PlayerConfig {
  // ── Playback ──────────────────────────────────────────────────────────────

  /// Start playing immediately after the source is opened.
  final bool autoPlay;

  /// Loop the current source when it reaches completion.
  final bool loop;

  /// Initial playback speed. Clamped to [0.25, 4.0].
  final double initialSpeed;

  /// Initial volume in the range [0.0, 1.0].
  final double initialVolume;

  // ── Seek ──────────────────────────────────────────────────────────────────

  /// Number of seconds to seek on double-tap or the skip buttons.
  ///
  /// Accepts 5, 10, or 30 to use the matching Material icon; any other value
  /// falls back to a generic arrow icon. Defaults to 10.
  final int seekSeconds;

  // ── Buffering / network (ExoPlayer LoadControl) ───────────────────────────

  /// Minimum duration of media kept buffered at all times, in milliseconds.
  /// ExoPlayer default: 25000.
  final int minBufferMs;

  /// Maximum duration of media the player will buffer, in milliseconds.
  /// ExoPlayer default: 6553600.
  final int maxBufferMs;

  /// Duration of media that must be buffered **before playback starts** (or
  /// resumes after a seek), in milliseconds. This is the main lever for fast
  /// startup — ExoPlayer's default is 3000; we lower it to 500 so network
  /// streams begin almost instantly.
  final int bufferForPlaybackMs;

  /// Duration of media that must be buffered to resume after a rebuffer (buffer
  /// depletion), in milliseconds. ExoPlayer default: 6000.
  final int bufferForPlaybackAfterRebufferMs;

  /// Seconds to wait while loading/buffering before showing a timeout error.
  /// Set to 0 to disable. Defaults to 30.
  final int loadingTimeoutSeconds;

  /// Number of automatic retry attempts before surfacing an error overlay.
  /// Retries use exponential backoff. Set to 0 to disable. Defaults to 3.
  final int autoRetryMaxAttempts;

  /// Base delay between automatic retries (doubles each attempt, capped at 30s).
  final Duration autoRetryBaseDelay;

  // ── Wakelock ──────────────────────────────────────────────────────────────

  /// Keep the screen on while the player is actively playing.
  final bool useWakelock;

  // ── UI ────────────────────────────────────────────────────────────────────

  /// Render the built-in controls overlay.
  ///
  /// Set to `false` to keep only the video surface (plus poster, buffering and
  /// error overlays) and stack your own controls on top of [PlayerView] —
  /// needed on platforms the built-in touch overlay does not serve, such as
  /// Android TV with D-pad navigation.
  final bool showControls;

  /// Seconds of inactivity before controls auto-hide. Set to 0 to disable.
  final int controlsTimeoutSeconds;

  /// Extra entries appended to the subtitle sheet, below the track list.
  ///
  /// The hook for host-app subtitle flows (downloading from an online
  /// provider, picking a local file, …). Shown even when the media has no
  /// subtitle tracks at all.
  final List<PlayerSheetAction> subtitleActions;

  /// Show a buffer/loading indicator while the player is buffering.
  final bool showBufferingIndicator;

  /// Whether to show the source title in the top controls bar.
  final bool showTitle;

  /// Whether to show the lock-screen button in the top controls bar.
  /// When locked, all gestures and controls are disabled until unlocked.
  final bool showLockButton;

  /// Whether to show the Picture-in-Picture button in the top controls bar.
  ///
  /// The button only appears when the platform actually supports PiP, i.e. on
  /// Android (with `android:supportsPictureInPicture="true"` declared on the
  /// host activity) and on iOS. It is never rendered on desktop or web.
  final bool showPipButton;

  /// Whether to show the inline volume control in the bottom bar.
  ///
  /// `null` (default) = automatic: shown on desktop/web (no hardware volume
  /// keys), hidden on mobile where the OS volume buttons are used instead.
  /// Set `true`/`false` to force it on or off.
  final bool? showVolumeControl;

  /// Accent colour used for the progress bar thumb and selection highlights.
  final Color accentColor;

  /// Visual style of the subtitles, passed straight through to
  /// better_player's subtitle drawer: font size/colour/family, outline,
  /// background colour, paddings and alignment.
  ///
  /// ```dart
  /// subtitlesConfiguration: BetterPlayerSubtitlesConfiguration(
  ///   fontSize: 18,
  ///   backgroundColor: Colors.black54,
  /// )
  /// ```
  final BetterPlayerSubtitlesConfiguration subtitlesConfiguration;

  /// Aspect ratio enforced on the video canvas. Null = use the stream's native
  /// ratio (recommended for adaptive streams).
  final double? aspectRatio;

  /// Initial scaling mode of the video. Toggle at runtime via the aspect-ratio
  /// button (desktop) or a pinch gesture (mobile).
  final VideoFit initialVideoFit;

  // ── Orientation ───────────────────────────────────────────────────────────

  /// Automatically lock the device orientation when the player mounts
  /// (mobile only). Uses [fullscreenOrientations] if set; otherwise waits for
  /// the first video frame and auto-detects landscape vs portrait from the
  /// video's aspect ratio. Restores system default when the player is disposed.
  final bool autoOrientation;

  // ── Fullscreen orientation ────────────────────────────────────────────────

  /// Device orientations allowed when the player enters fullscreen on mobile.
  ///
  /// When `null` (default) the player auto-detects the video's aspect ratio
  /// and locks to landscape for horizontal videos or portrait for vertical ones.
  ///
  /// Supply an explicit list to override that logic, e.g.:
  /// ```dart
  /// fullscreenOrientations: [
  ///   DeviceOrientation.landscapeLeft,
  ///   DeviceOrientation.landscapeRight,
  /// ]
  /// ```
  final List<DeviceOrientation>? fullscreenOrientations;

  // ── Telemetry ─────────────────────────────────────────────────────────────

  /// Playback telemetry reporting against your API.
  ///
  /// When set, the player emits `start` / `progress` / `end` / `error` events
  /// to `POST {apiUrl}` with a bearer token, queues them on
  /// disk and retries with backoff. `null` (default) disables reporting
  /// entirely — nothing is measured and no network call is made.
  ///
  /// Only sources carrying a [PlayerSource.contentId] are reported.
  final TelemetryConfig? telemetry;

  // ── Host-app callbacks ────────────────────────────────────────────────────

  /// Called when playback reaches the end of the source.
  final VoidCallback? onCompleted;

  /// Called when the player enters an error state.
  final void Function(String message)? onError;

  /// Called at most once per second during playback with the current position.
  final void Function(Duration position)? onPositionChanged;

  const PlayerConfig({
    this.autoPlay = true,
    this.loop = false,
    this.initialSpeed = 1.0,
    this.initialVolume = 1.0,
    this.seekSeconds = 10,
    this.minBufferMs = 25000,
    this.maxBufferMs = 6553600,
    this.bufferForPlaybackMs = 500,
    this.bufferForPlaybackAfterRebufferMs = 6000,
    this.loadingTimeoutSeconds = 30,
    this.autoRetryMaxAttempts = 3,
    this.autoRetryBaseDelay = const Duration(seconds: 2),
    this.useWakelock = true,
    this.showControls = true,
    this.controlsTimeoutSeconds = 4,
    this.subtitleActions = const [],
    this.showBufferingIndicator = true,
    this.showTitle = true,
    this.showLockButton = true,
    this.showPipButton = true,
    this.showVolumeControl,
    this.accentColor = const Color(0xFFE50914),
    this.subtitlesConfiguration = const BetterPlayerSubtitlesConfiguration(),
    this.aspectRatio,
    this.initialVideoFit = VideoFit.contain,
    this.autoOrientation = false,
    this.fullscreenOrientations,
    this.telemetry,
    this.onCompleted,
    this.onError,
    this.onPositionChanged,
  });

  PlayerConfig copyWith({
    bool? autoPlay,
    bool? loop,
    double? initialSpeed,
    double? initialVolume,
    int? seekSeconds,
    int? minBufferMs,
    int? maxBufferMs,
    int? bufferForPlaybackMs,
    int? bufferForPlaybackAfterRebufferMs,
    int? loadingTimeoutSeconds,
    int? autoRetryMaxAttempts,
    Duration? autoRetryBaseDelay,
    bool? useWakelock,
    bool? showControls,
    int? controlsTimeoutSeconds,
    List<PlayerSheetAction>? subtitleActions,
    bool? showBufferingIndicator,
    bool? showTitle,
    bool? showLockButton,
    bool? showPipButton,
    bool? showVolumeControl,
    Color? accentColor,
    BetterPlayerSubtitlesConfiguration? subtitlesConfiguration,
    double? aspectRatio,
    VideoFit? initialVideoFit,
    bool? autoOrientation,
    List<DeviceOrientation>? fullscreenOrientations,
    TelemetryConfig? telemetry,
    VoidCallback? onCompleted,
    void Function(String)? onError,
    void Function(Duration)? onPositionChanged,
  }) {
    return PlayerConfig(
      autoPlay: autoPlay ?? this.autoPlay,
      loop: loop ?? this.loop,
      initialSpeed: initialSpeed ?? this.initialSpeed,
      initialVolume: initialVolume ?? this.initialVolume,
      seekSeconds: seekSeconds ?? this.seekSeconds,
      minBufferMs: minBufferMs ?? this.minBufferMs,
      maxBufferMs: maxBufferMs ?? this.maxBufferMs,
      bufferForPlaybackMs: bufferForPlaybackMs ?? this.bufferForPlaybackMs,
      bufferForPlaybackAfterRebufferMs: bufferForPlaybackAfterRebufferMs ??
          this.bufferForPlaybackAfterRebufferMs,
      loadingTimeoutSeconds: loadingTimeoutSeconds ?? this.loadingTimeoutSeconds,
      autoRetryMaxAttempts: autoRetryMaxAttempts ?? this.autoRetryMaxAttempts,
      autoRetryBaseDelay: autoRetryBaseDelay ?? this.autoRetryBaseDelay,
      useWakelock: useWakelock ?? this.useWakelock,
      showControls: showControls ?? this.showControls,
      controlsTimeoutSeconds:
          controlsTimeoutSeconds ?? this.controlsTimeoutSeconds,
      subtitleActions: subtitleActions ?? this.subtitleActions,
      showBufferingIndicator:
          showBufferingIndicator ?? this.showBufferingIndicator,
      showTitle: showTitle ?? this.showTitle,
      showLockButton: showLockButton ?? this.showLockButton,
      showPipButton: showPipButton ?? this.showPipButton,
      showVolumeControl: showVolumeControl ?? this.showVolumeControl,
      accentColor: accentColor ?? this.accentColor,
      subtitlesConfiguration:
          subtitlesConfiguration ?? this.subtitlesConfiguration,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      initialVideoFit: initialVideoFit ?? this.initialVideoFit,
      autoOrientation: autoOrientation ?? this.autoOrientation,
      fullscreenOrientations:
          fullscreenOrientations ?? this.fullscreenOrientations,
      telemetry: telemetry ?? this.telemetry,
      onCompleted: onCompleted ?? this.onCompleted,
      onError: onError ?? this.onError,
      onPositionChanged: onPositionChanged ?? this.onPositionChanged,
    );
  }
}
