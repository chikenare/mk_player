import 'package:better_player/better_player.dart';

// Shared between the touch sheets (settings_sheet.dart) and the TV side panel
// (tv_tracks_panel.dart) so both name a track the same way.

String audioTrackLabel(BetterPlayerAsmsAudioTrack track, int index) {
  final label = track.label;
  if (label != null && label.isNotEmpty) return label;
  final lang = track.language;
  if (lang != null && lang.isNotEmpty) return lang.toUpperCase();
  return 'Track ${index + 1}';
}

String subtitleTrackLabel(BetterPlayerSubtitlesSource source, int index) {
  if (source.type == BetterPlayerSubtitlesSourceType.none) return 'Off';
  final name = source.name;
  if (name != null && name.isNotEmpty && name != 'Default subtitles') {
    return name;
  }
  return 'Subtitle ${index + 1}';
}
