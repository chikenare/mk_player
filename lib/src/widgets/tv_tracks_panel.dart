import 'package:better_player_plus/better_player_plus.dart'
    show BetterPlayerSubtitlesSource;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent;

import '../controller.dart';
import '../models/player_config.dart';
import '../tv/remote_key.dart';
import '../tv/tv_focusable.dart';
import 'listenable_selector.dart';
import 'track_labels.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TV track panel
// ─────────────────────────────────────────────────────────────────────────────
//
// The touch build asks one question per sheet, sliding up from the bottom over
// the video. A remote cannot afford that: every extra screen is another four
// presses, and a sheet that covers the lower third hides the subtitles the user
// is trying to choose. So on TV both lists live in a single panel pinned to the
// right — audio in one column, subtitles in the next, sized to the number of
// tracks and never wider than it needs to be. Selecting applies immediately and
// keeps the panel open, so a wrong guess is one press away from being fixed;
// Back (or the barrier) closes it.

/// Column width. Fits ~22 characters of a track name at 14px before eliding —
/// enough for "Spanish (Latin America)".
const double _kColumnWidth = 252;

/// Opens the audio + subtitle panel. [config] supplies
/// [PlayerConfig.subtitleActions]; it defaults to the controller's own.
Future<void> showTvTracksPanel(
  BuildContext context,
  CustomPlayerController controller, {
  PlayerConfig? config,
}) {
  return showGeneralDialog<void>(
    context: context,
    // Dim, not black: the video keeps playing behind the panel and the point of
    // picking a subtitle is being able to see it land.
    barrierColor: const Color(0x4D000000),
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (_, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.12, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (_, _, _) => _TvTracksPanel(
      controller: controller,
      config: config ?? controller.config,
    ),
  );
}

class _TvTracksPanel extends StatelessWidget {
  final CustomPlayerController controller;
  final PlayerConfig config;

  const _TvTracksPanel({required this.controller, required this.config});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Focus(
      // Never a focus target itself — it only watches the keys on their way up
      // from whichever tile holds focus, so Back closes the panel on remotes
      // that report it as a key rather than as a system pop.
      skipTraversal: true,
      onKeyEvent: (_, KeyEvent event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (mapRemoteKey(event.logicalKey) != RemoteKey.back) {
          return KeyEventResult.ignored;
        }
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
      },
      child: Align(
        alignment: Alignment.centerRight,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              // Hugs its content vertically; the cap only matters for a source
              // with more tracks than the screen can hold, which then scrolls.
              constraints: BoxConstraints(
                maxHeight: size.height - 40,
                maxWidth: size.width * 0.62,
              ),
              // Track lists and the current selection change rarely — a
              // selector keeps the panel off the controller's 300ms tick.
              child: ListenableSelector<Object>(
                listenable: controller,
                selector: () => Object.hash(
                  controller.audioTracks.length,
                  controller.selectedAudioTrack?.id,
                  controller.subtitleSources.length,
                  controller.selectedSubtitle,
                ),
                builder: (context, _) => _buildPanel(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final audioTracks = controller.audioTracks;
    final actions = config.subtitleActions;
    // Mirrors the touch sheet: with no real subtitle track there is nothing to
    // list, not even the "off" entry better_player always keeps in the list.
    final subtitleTracks = controller.hasSubtitles
        ? controller.subtitleSources
        : const <BetterPlayerSubtitlesSource>[];

    // Same rule as the touch bar: a lone audio track is not a choice, and the
    // subtitle column earns its place as soon as there is a track *or* a host
    // action to offer.
    final showAudio = audioTracks.length > 1;
    final showSubtitles = subtitleTracks.isNotEmpty || actions.isNotEmpty;

    // Focus opens in the leftmost column, on the entry already in use. A
    // selection that is not in the list — or none at all — falls back to the
    // first row, so the panel never opens with nothing focused for the D-pad.
    final selectedAudioId = controller.selectedAudioTrack?.id;
    final selectedSubtitle = controller.selectedSubtitle;
    var audioFocus = -1;
    var subtitleFocus = -1;
    var actionFocus = -1;
    if (showAudio) {
      final found = audioTracks.indexWhere((t) => t.id == selectedAudioId);
      audioFocus = found >= 0 ? found : 0;
    } else if (showSubtitles) {
      final found = selectedSubtitle == null
          ? -1
          : subtitleTracks.indexOf(selectedSubtitle);
      if (found >= 0) {
        subtitleFocus = found;
      } else if (subtitleTracks.isNotEmpty) {
        subtitleFocus = 0;
      } else {
        actionFocus = 0; // the host actions are all there is
      }
    }

    final sections = <Widget>[
      if (showAudio)
        _Section(
          title: 'Audio',
          children: [
            for (var i = 0; i < audioTracks.length; i++)
              _PanelTile(
                label: audioTrackLabel(audioTracks[i], i),
                selected: audioTracks[i].id == selectedAudioId,
                autofocus: i == audioFocus,
                // Applies in place: the check mark moves, the panel stays.
                onPressed: () => controller.setAudioTrack(audioTracks[i]),
              ),
          ],
        ),
      if (showSubtitles)
        _Section(
          title: 'Subtitles',
          children: [
            for (var i = 0; i < subtitleTracks.length; i++)
              _PanelTile(
                label: subtitleTrackLabel(subtitleTracks[i], i),
                selected: subtitleTracks[i] == selectedSubtitle,
                autofocus: i == subtitleFocus,
                onPressed: () => controller.setSubtitle(subtitleTracks[i]),
              ),
            // Host-app entries (e.g. "search subtitles online"). The panel is
            // dismissed first so the callback can push a route of its own.
            if (actions.isNotEmpty) ...[
              if (subtitleTracks.isNotEmpty) const _SectionDivider(),
              for (var i = 0; i < actions.length; i++)
                _PanelTile(
                  label: actions[i].label,
                  icon: actions[i].icon,
                  selected: false,
                  autofocus: i == actionFocus,
                  onPressed: () {
                    Navigator.of(context).pop();
                    actions[i].onTap(context);
                  },
                ),
            ],
          ],
        ),
    ];

    // A Material, not a DecoratedBox: this route is pushed by
    // showGeneralDialog, which supplies none of its own, and text without a
    // Material ancestor inherits the framework's "you forgot one" style —
    // yellow double underlines. It also draws the elevation shadow for us.
    return Material(
      type: MaterialType.card,
      color: const Color(0xF2141414),
      elevation: 16,
      shadowColor: Colors.black,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: sections.isEmpty
            ? const SizedBox(
                width: _kColumnWidth,
                child: _EmptyHint('No alternate tracks'),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    sections[i],
                  ],
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section — a titled column, as tall as its entries
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kColumnWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
              ),
            ),
          ),
          // Loose fit: the list takes exactly the height its rows need, and
          // only starts scrolling once that exceeds the panel's cap.
          Flexible(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Divider(height: 1, thickness: 1, color: Colors.white12),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel tile
// ─────────────────────────────────────────────────────────────────────────────

class _PanelTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onPressed;

  /// Host actions carry their own icon; tracks are identified by the check
  /// mark alone — a column of identical headphones is just noise.
  final IconData? icon;

  const _PanelTile({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      autofocus: autofocus,
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: focused
              ? Colors.white.withAlpha(48)
              : selected
                  ? Colors.white.withAlpha(20)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: focused ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: icon != null
                  ? Icon(icon, size: 16, color: Colors.white70)
                  : selected
                      ? const Icon(Icons.check_rounded,
                          size: 17, color: Colors.white)
                      : null,
            ),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected || focused ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white38, fontSize: 13),
      ),
    );
  }
}
