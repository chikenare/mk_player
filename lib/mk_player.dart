// mk_player — A highly reusable Flutter video player built on
// better_player_plus (ExoPlayer on Android).
//
// Import this single barrel file in your host application:
//   import 'package:mk_player/mk_player.dart';
//
// See INTEGRATION.md for the full setup guide.

// ── Public models ────────────────────────────────────────────────────────────
export 'src/models/player_action.dart' show PlayerSheetAction;
export 'src/models/player_config.dart';
export 'src/models/player_source.dart';
export 'src/models/external_subtitle.dart' show ExternalSubtitle;
export 'src/models/storyboard.dart' show Storyboard, StoryboardEntry;
export 'src/models/video_fit.dart' show VideoFit;
export 'src/models/video_format.dart' show PlayerVideoFormat;

// ── Playback measurement ──────────────────────────────────────────────────────
// What the player measures, independent of where it is reported. `PlayerConfig
// .onPlaybackEvent` receives these; `TelemetryEvent`/`TelemetryEventType` are
// the former names, kept as aliases.
export 'src/playback/playback_event.dart'
    show PlaybackEvent, PlaybackEventType, TelemetryEvent, TelemetryEventType;
export 'src/playback/playback_session_tracker.dart'
    show PlaybackEventSink, PlaybackSessionOptions, PlaybackSessionTracker;

// ── Telemetry reporting (the built-in API transport) ──────────────────────────
export 'src/telemetry/telemetry_config.dart'
    show TelemetryConfig, TelemetryDeviceType, TelemetryKind;
export 'src/telemetry/telemetry_reporter.dart' show TelemetryReporter;

// ── Core controller ───────────────────────────────────────────────────────────
export 'src/controller.dart' show CustomPlayerController, MkPlayerState;

// ── UI ────────────────────────────────────────────────────────────────────────
export 'src/player_view.dart' show PlayerView;

// ── Re-export the better_player track/subtitle types host apps may need ───────
export 'package:better_player_plus/better_player_plus.dart'
    show
        BetterPlayerAsmsAudioTrack,
        BetterPlayerAsmsTrack,
        BetterPlayerSubtitlesConfiguration,
        BetterPlayerSubtitlesSource,
        BetterPlayerSubtitlesSourceType;
