import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:media_kit_video/media_kit_video.dart' show SubtitleViewConfiguration;

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

  // ── Buffering / network ───────────────────────────────────────────────────

  /// Network buffer size in bytes fed to libmpv. Defaults to 32 MB.
  final int bufferSize;

  /// Seconds to wait while loading/buffering before showing a timeout error.
  /// Set to 0 to disable. Defaults to 30.
  final int loadingTimeoutSeconds;

  /// Number of automatic retry attempts before surfacing an error overlay.
  /// Retries use exponential backoff. Set to 0 to disable. Defaults to 3.
  final int autoRetryMaxAttempts;

  /// Base delay between automatic retries (doubles each attempt, capped at 30s).
  final Duration autoRetryBaseDelay;

  // ── Hardware acceleration ─────────────────────────────────────────────────

  /// Enable platform GPU decoding. Disable if you encounter codec issues.
  final bool enableHardwareAcceleration;

  // ── Wakelock ──────────────────────────────────────────────────────────────

  /// Keep the screen on while the player is actively playing.
  final bool useWakelock;

  // ── UI ────────────────────────────────────────────────────────────────────

  /// Seconds of inactivity before controls auto-hide. Set to 0 to disable.
  final int controlsTimeoutSeconds;

  /// Show a buffer/loading indicator while the player is buffering.
  final bool showBufferingIndicator;

  /// Whether to show the source title in the top controls bar.
  final bool showTitle;

  /// Whether to show the lock-screen button in the top controls bar.
  /// When locked, all gestures and controls are disabled until unlocked.
  final bool showLockButton;

  /// Whether to show the inline volume control in the bottom bar.
  ///
  /// `null` (default) = automatic: shown on desktop/web (no hardware volume
  /// keys), hidden on mobile where the OS volume buttons are used instead.
  /// Set `true`/`false` to force it on or off.
  final bool? showVolumeControl;

  /// Accent colour used for the progress bar thumb and selection highlights.
  final Color accentColor;

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

  // ── Subtitles ─────────────────────────────────────────────────────────────

  /// Styling for the rendered subtitle overlay (font, colour, background,
  /// alignment, padding). Pass a custom [SubtitleViewConfiguration] to fully
  /// control the look. `null` uses media_kit's default style.
  final SubtitleViewConfiguration? subtitleViewConfiguration;

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
    this.bufferSize = 32 * 1024 * 1024,
    this.loadingTimeoutSeconds = 30,
    this.autoRetryMaxAttempts = 3,
    this.autoRetryBaseDelay = const Duration(seconds: 2),
    this.enableHardwareAcceleration = true,
    this.useWakelock = true,
    this.controlsTimeoutSeconds = 4,
    this.showBufferingIndicator = true,
    this.showTitle = true,
    this.showLockButton = true,
    this.showVolumeControl,
    this.accentColor = const Color(0xFFE50914),
    this.aspectRatio,
    this.initialVideoFit = VideoFit.contain,
    this.autoOrientation = false,
    this.fullscreenOrientations,
    this.subtitleViewConfiguration,
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
    int? bufferSize,
    int? loadingTimeoutSeconds,
    int? autoRetryMaxAttempts,
    Duration? autoRetryBaseDelay,
    bool? enableHardwareAcceleration,
    bool? useWakelock,
    int? controlsTimeoutSeconds,
    bool? showBufferingIndicator,
    bool? showTitle,
    bool? showLockButton,
    bool? showVolumeControl,
    Color? accentColor,
    double? aspectRatio,
    VideoFit? initialVideoFit,
    bool? autoOrientation,
    List<DeviceOrientation>? fullscreenOrientations,
    SubtitleViewConfiguration? subtitleViewConfiguration,
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
      bufferSize: bufferSize ?? this.bufferSize,
      loadingTimeoutSeconds: loadingTimeoutSeconds ?? this.loadingTimeoutSeconds,
      autoRetryMaxAttempts: autoRetryMaxAttempts ?? this.autoRetryMaxAttempts,
      autoRetryBaseDelay: autoRetryBaseDelay ?? this.autoRetryBaseDelay,
      enableHardwareAcceleration:
          enableHardwareAcceleration ?? this.enableHardwareAcceleration,
      useWakelock: useWakelock ?? this.useWakelock,
      controlsTimeoutSeconds:
          controlsTimeoutSeconds ?? this.controlsTimeoutSeconds,
      showBufferingIndicator:
          showBufferingIndicator ?? this.showBufferingIndicator,
      showTitle: showTitle ?? this.showTitle,
      showLockButton: showLockButton ?? this.showLockButton,
      showVolumeControl: showVolumeControl ?? this.showVolumeControl,
      accentColor: accentColor ?? this.accentColor,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      initialVideoFit: initialVideoFit ?? this.initialVideoFit,
      autoOrientation: autoOrientation ?? this.autoOrientation,
      fullscreenOrientations:
          fullscreenOrientations ?? this.fullscreenOrientations,
      subtitleViewConfiguration:
          subtitleViewConfiguration ?? this.subtitleViewConfiguration,
      onCompleted: onCompleted ?? this.onCompleted,
      onError: onError ?? this.onError,
      onPositionChanged: onPositionChanged ?? this.onPositionChanged,
    );
  }
}
