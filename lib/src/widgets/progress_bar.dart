import 'package:flutter/material.dart';

import '../models/storyboard.dart';
import 'thumbnail_preview.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlayerProgressBar
// ─────────────────────────────────────────────────────────────────────────────

class PlayerProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Color accentColor;

  /// Optional storyboard. When provided, a thumbnail popup appears above the
  /// thumb while the user is scrubbing.
  final Storyboard? storyboard;

  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;

  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.accentColor,
    this.storyboard,
    this.onSeek,
    this.onScrubStart,
    this.onScrubEnd,
  });

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  double? _dragValue;

  double get _progress {
    if (widget.duration.inMilliseconds == 0) return 0.0;
    return (widget.position.inMilliseconds / widget.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  double get _bufferedProgress {
    if (widget.duration.inMilliseconds == 0) return 0.0;
    return (widget.buffered.inMilliseconds / widget.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  Duration get _scrubPosition {
    final ms = ((_dragValue ?? _progress) * widget.duration.inMilliseconds)
        .round()
        .clamp(0, widget.duration.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  void _onChangeStart(double v) {
    setState(() => _dragValue = v);
    widget.onScrubStart?.call();
  }

  void _onChanged(double v) => setState(() => _dragValue = v);

  void _onChangeEnd(double v) {
    final ms = (v * widget.duration.inMilliseconds).round();
    widget.onSeek?.call(Duration(milliseconds: ms));
    setState(() => _dragValue = null);
    widget.onScrubEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = _dragValue ?? _progress;
    final isScrubbing = _dragValue != null;

    const thumbR = 7.0;
    const overlayR = 16.0;
    // The Slider horizontal padding = overlayRadius (Flutter internal).
    const hPad = overlayR;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackW = constraints.maxWidth - 2 * hPad;
        final thumbX = hPad + trackW * displayValue;

        // Thumbnail popup dimensions
        const popupW = 144.0;
        final clampedX =
            (thumbX - popupW / 2).clamp(4.0, constraints.maxWidth - popupW - 4);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Thumbnail popup ──────────────────────────────────────────────
            if (isScrubbing)
              Positioned(
                bottom: 28,
                left: clampedX,
                child: ThumbnailPreview(
                  entry: widget.storyboard?.entryAt(_scrubPosition),
                  position: _scrubPosition,
                  width: popupW,
                ),
              ),

            // ── Slider ───────────────────────────────────────────────────────
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3.0,
                thumbShape: const _TinyThumbShape(thumbRadius: thumbR),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: overlayR),
                activeTrackColor: widget.accentColor,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: widget.accentColor.withAlpha(51),
                secondaryActiveTrackColor: Colors.white38,
              ),
              child: Slider(
                value: displayValue,
                secondaryTrackValue: _bufferedProgress,
                onChanged: widget.onSeek != null ? _onChanged : null,
                onChangeStart:
                    widget.onSeek != null ? _onChangeStart : null,
                onChangeEnd:
                    widget.onSeek != null ? _onChangeEnd : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Custom thumb ──────────────────────────────────────────────────────────────

class _TinyThumbShape extends SliderComponentShape {
  final double thumbRadius;
  const _TinyThumbShape({required this.thumbRadius});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(thumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final r = Tween<double>(
      begin: thumbRadius * 0.6,
      end: thumbRadius,
    ).evaluate(activationAnimation);
    context.canvas.drawCircle(
      center,
      r,
      Paint()..color = sliderTheme.thumbColor ?? Colors.white,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duration formatter — shared by progress bar and thumbnail preview
// ─────────────────────────────────────────────────────────────────────────────

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
