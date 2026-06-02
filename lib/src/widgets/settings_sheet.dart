import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../controller.dart';

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
            accentColor: controller.config.accentColor,
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
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tracks.length; i++)
                _TrackTile(
                  label: _trackLabel(tracks[i].title, tracks[i].language, i),
                  icon: Icons.headphones_rounded,
                  isSelected: tracks[i] == controller.selectedAudioTrack,
                  accentColor: controller.config.accentColor,
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

Future<void> showSubtitleSheet(
  BuildContext context,
  CustomPlayerController controller,
) {
  return _show(
    context,
    _SheetScaffold(
      title: 'Subtitles',
      child: ListenableBuilder(
        listenable: controller,
        builder: (ctx, _) {
          final tracks = controller.subtitleTracks; // sentinels already filtered
          final external = controller.externalSubtitles;
          final accent = controller.config.accentColor;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TrackTile(
                label: 'Off',
                icon: Icons.subtitles_off_rounded,
                isSelected:
                    controller.selectedSubtitleTrack == SubtitleTrack.no(),
                accentColor: accent,
                onTap: () {
                  controller.disableSubtitles();
                  Navigator.of(ctx).pop();
                },
              ),

              // Embedded subtitle tracks
              for (var i = 0; i < tracks.length; i++)
                _TrackTile(
                  label: _trackLabel(tracks[i].title, tracks[i].language, i),
                  icon: Icons.closed_caption_rounded,
                  isSelected: tracks[i] == controller.selectedSubtitleTrack,
                  accentColor: accent,
                  onTap: () {
                    controller.setSubtitleTrack(tracks[i]);
                    Navigator.of(ctx).pop();
                  },
                ),

              // External subtitles supplied by the host app
              for (var i = 0; i < external.length; i++)
                _TrackTile(
                  label: external[i].title ??
                      external[i].language?.toUpperCase() ??
                      'External ${i + 1}',
                  icon: Icons.translate_rounded,
                  isSelected:
                      controller.isExternalSubtitleSelected(external[i]),
                  accentColor: accent,
                  onTap: () {
                    controller.setExternalSubtitle(external[i]);
                    Navigator.of(ctx).pop();
                  },
                ),

              if (tracks.isEmpty && external.isEmpty)
                const _EmptyHint('No subtitles available'),
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
  final Color accentColor;
  final ValueChanged<double> onSelect;

  const _SpeedChipRow({
    required this.current,
    required this.accentColor,
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
        return GestureDetector(
          onTap: () => onSelect(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? accentColor.withAlpha(35) : Colors.white10,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? accentColor : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? accentColor : Colors.white70,
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
  final Color accentColor;
  final VoidCallback onTap;

  const _TrackTile({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18, color: isSelected ? accentColor : Colors.white38),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 13),
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

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _trackLabel(String? title, String? lang, int index) {
  if (title != null && title.isNotEmpty) return title;
  if (lang != null && lang.isNotEmpty) return lang.toUpperCase();
  return 'Track ${index + 1}';
}
