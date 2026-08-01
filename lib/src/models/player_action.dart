import 'package:flutter/widgets.dart';

/// An extra, host-supplied entry rendered inside one of the player's bottom
/// sheets (currently the subtitle sheet, via [PlayerConfig.subtitleActions]).
///
/// Use it to plug app-specific flows into the built-in UI without forking the
/// package — e.g. an "Search subtitles online" action that opens the host app's
/// own OpenSubtitles browser:
///
/// ```dart
/// PlayerConfig(
///   subtitleActions: [
///     PlayerSheetAction(
///       icon: Icons.search_rounded,
///       label: 'Search online…',
///       onTap: (context) => showMySubtitleSearchSheet(context),
///     ),
///   ],
/// )
/// ```
///
/// The sheet closes itself before [onTap] runs, so the callback receives a
/// context that is safe to push routes or open another sheet from.
class PlayerSheetAction {
  /// Leading icon shown in the tile.
  final IconData icon;

  /// Text label of the tile.
  final String label;

  /// Invoked when the tile is tapped, after the sheet has been dismissed.
  final void Function(BuildContext context) onTap;

  const PlayerSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}
