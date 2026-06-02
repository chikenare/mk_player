// mk_player — A highly reusable Flutter video player built on
// better_player_plus (ExoPlayer on Android).
//
// Import this single barrel file in your host application:
//   import 'package:mk_player/mk_player.dart';
//
// See INTEGRATION.md for the full setup guide.

// ── Public models ────────────────────────────────────────────────────────────
export 'src/models/player_config.dart';
export 'src/models/player_source.dart';
export 'src/models/external_subtitle.dart' show ExternalSubtitle;
export 'src/models/storyboard.dart' show Storyboard, StoryboardEntry;
export 'src/models/video_fit.dart' show VideoFit;

// ── Core controller ───────────────────────────────────────────────────────────
export 'src/controller.dart' show CustomPlayerController, MkPlayerState;

// ── UI ────────────────────────────────────────────────────────────────────────
export 'src/player_view.dart' show PlayerView;

// ── Re-export the better_player track/subtitle types host apps may need ───────
export 'package:better_player_plus/better_player_plus.dart'
    show
        BetterPlayerAsmsAudioTrack,
        BetterPlayerAsmsTrack,
        BetterPlayerSubtitlesSource,
        BetterPlayerSubtitlesSourceType;
