import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../models/player_config.dart';
import '../tv/tv_focusable.dart';
import 'track_labels.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry points — focused sheets (Netflix/Apple TV+ style)
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showSpeedSheet(
  BuildContext context,
  CustomPlayerController controller,
) {
  return _show(
    context,
    _SheetScaffold(
      title: 'Playback Speed',
      child: ListenableBuilder(
        listenable: controller,
        builder: (_, _) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: _SpeedChipRow(
            current: controller.speed,
            onSelect: controller.setSpeed,
          ),
        ),
      ),
    ),
  );
}

Future<void> showAudioSheet(
  BuildContext context,
  CustomPlayerController controller,
) {
  return _show(
    context,
    _SheetScaffold(
      title: 'Audio',
      child: ListenableBuilder(
        listenable: controller,
        builder: (ctx, _) {
          final tracks = controller.audioTracks;
          if (tracks.isEmpty) {
            return const _EmptyHint('No audio tracks available');
          }
          final selectedId = controller.selectedAudioTrack?.id;
          final hasSelection = tracks.any((t) => t.id == selectedId);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tracks.length; i++)
                _TrackTile(
                  label: audioTrackLabel(tracks[i], i),
                  icon: Icons.headphones_rounded,
                  isSelected: tracks[i].id == selectedId,
                  autofocus: hasSelection
                      ? tracks[i].id == selectedId
                      : i == 0,
                  onTap: () {
                    controller.setAudioTrack(tracks[i]);
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// [config] defaults to the controller's own configuration; pass the one the
/// view was built with when it overrides it (e.g. host actions whose labels are
/// resolved from a [BuildContext]).
Future<void> showSubtitleSheet(
  BuildContext context,
  CustomPlayerController controller, {
  PlayerConfig? config,
}) {
  return _show(
    context,
    _SheetScaffold(
      title: 'Subtitles',
      child: ListenableBuilder(
        listenable: controller,
        builder: (ctx, _) {
          final sources = controller.subtitleSources;
          final selected = controller.selectedSubtitle;
          final cfg = config ?? controller.config;
          final actions = cfg.subtitleActions;

          final hasSelection = sources.contains(selected);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!controller.hasSubtitles)
                const _EmptyHint('No subtitles available')
              else
                for (var i = 0; i < sources.length; i++)
                  _TrackTile(
                    label: subtitleTrackLabel(sources[i], i),
                    icon:
                        sources[i].type == BetterPlayerSubtitlesSourceType.none
                            ? Icons.subtitles_off_rounded
                            : Icons.closed_caption_rounded,
                    isSelected: sources[i] == selected,
                    autofocus:
                        hasSelection ? sources[i] == selected : i == 0,
                    onTap: () {
                      controller.setSubtitle(sources[i]);
                      Navigator.of(ctx).pop();
                    },
                  ),
              // Host-app entries (e.g. "search subtitles online"). The sheet is
              // dismissed first so the callback can safely push its own route.
              if (actions.isNotEmpty) ...[
                const _SheetDivider(),
                for (final action in actions)
                  _TrackTile(
                    label: action.label,
                    icon: action.icon,
                    isSelected: false,
                    // With no tracks at all, the host actions are the only
                    // thing a remote can land on.
                    autofocus: !controller.hasSubtitles &&
                        identical(action, actions.first),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      action.onTap(context);
                    },
                  ),
              ],
            ],
          );
        },
      ),
    ),
  );
}

Future<void> _show(BuildContext context, Widget sheet) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Explicitly off: _SheetScaffold draws its own handle inside the rounded
    // card. Left to the default this follows the *host app's*
    // BottomSheetThemeData, and an app that enables drag handles globally gets
    // a second one — floating above the card, because our background is
    // transparent and Material insets the content by 48px to make room for it.
    showDragHandle: false,
    builder: (_) => sheet,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet scaffold — drag handle + title + scrollable content
// ─────────────────────────────────────────────────────────────────────────────

class _SheetScaffold extends StatelessWidget {
  final String title;
  final Widget child;

  const _SheetScaffold({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF161616),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: SafeArea(top: false, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Speed chip row
// ─────────────────────────────────────────────────────────────────────────────

const _kSpeedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

class _SpeedChipRow extends StatelessWidget {
  final double current;
  final ValueChanged<double> onSelect;

  const _SpeedChipRow({
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kSpeedOptions.map((s) {
        final selected = (current - s).abs() < 0.01;
        final label = s == 1.0 ? '1×' : '$s×';
        return TvFocusable(
          onPressed: () => onSelect(s),
          // The current speed is where a remote should land.
          autofocus: selected,
          builder: (_, focused) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withAlpha(45)
                  : selected
                      ? Colors.white.withAlpha(28)
                      : Colors.white10,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: focused
                    ? Colors.white
                    : selected
                        ? Colors.white54
                        : Colors.transparent,
                width: focused ? 2 : 1.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected || focused ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Track tile
// ─────────────────────────────────────────────────────────────────────────────

class _TrackTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  /// Takes focus when the sheet opens, so a remote lands on a real entry
  /// instead of nowhere. Set on the selected row (or the first one).
  final bool autofocus;

  const _TrackTile({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onTap,
      autofocus: autofocus,
      // Selection and focus are both drawn in white, at different weights:
      // a tint for the chosen track, a tint plus a ring for the focused one.
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: focused
              ? Colors.white.withAlpha(45)
              : isSelected
                  ? Colors.white.withAlpha(20)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: focused ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18, color: isSelected ? Colors.white : Colors.white38),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected || focused ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: Icon(Icons.check_rounded,
                      color: Color(0xFF161616), size: 13),
                ),
              )
            else
              const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Divider between the track list and the host-app actions
// ─────────────────────────────────────────────────────────────────────────────

class _SheetDivider extends StatelessWidget {
  const _SheetDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Divider(height: 1, thickness: 1, color: Colors.white12),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty hint
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white38, fontSize: 13),
      ),
    );
  }
}

