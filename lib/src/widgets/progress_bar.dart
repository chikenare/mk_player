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

  /// Target of an in-flight D-pad scrub. While set, the thumb, the elapsed
  /// time and the thumbnail follow it instead of the live position — the seek
  /// itself only happens once the user stops pressing.
  final Duration? previewPosition;

  /// Focus state under a remote: null when the bar is not a focus target
  /// (touch/mouse), true/false when it is.
  final bool? tvFocused;

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
    this.previewPosition,
    this.tvFocused,
    this.onSeek,
    this.onScrubStart,
    this.onScrubEnd,
  });

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  double? _dragValue;
  bool _dragging = false;

  // After releasing a scrub, the async seek takes a moment; keep showing the
  // released value until position catches up (or a timeout passes) so the
  // thumb doesn't flash back to the pre-seek position.
  Duration? _pendingSeek;
  DateTime? _pendingSeekAt;

  @override
  void didUpdateWidget(covariant PlayerProgressBar old) {
    super.didUpdateWidget(old);
    final pending = _pendingSeek;
    if (pending == null) return;
    final caughtUp =
        (widget.position - pending).abs() < const Duration(milliseconds: 900);
    final timedOut = _pendingSeekAt != null &&
        DateTime.now().difference(_pendingSeekAt!) >
            const Duration(milliseconds: 2500);
    if (caughtUp || timedOut) {
      _pendingSeek = null;
      _pendingSeekAt = null;
      _dragValue = null;
    }
  }

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

  /// The D-pad scrub target as a track fraction, when one is pending.
  double? get _previewProgress {
    final preview = widget.previewPosition;
    if (preview == null || widget.duration.inMilliseconds == 0) return null;
    return (preview.inMilliseconds / widget.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  Duration get _scrubPosition {
    final ms = ((_dragValue ?? _previewProgress ?? _progress) *
            widget.duration.inMilliseconds)
        .round()
        .clamp(0, widget.duration.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  void _onChangeStart(double v) {
    setState(() {
      _dragValue = v;
      _dragging = true;
    });
    widget.onScrubStart?.call();
  }

  void _onChanged(double v) => setState(() => _dragValue = v);

  void _onChangeEnd(double v) {
    final target = Duration(
      milliseconds: (v * widget.duration.inMilliseconds).round(),
    );
    widget.onSeek?.call(target);
    setState(() {
      // Hold the released value; didUpdateWidget clears it once the player's
      // reported position reaches the target.
      _dragging = false;
      _pendingSeek = target;
      _pendingSeekAt = DateTime.now();
    });
    widget.onScrubEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = _dragValue ?? _previewProgress ?? _progress;
    // A D-pad scrub shows the same thumbnail popup a finger drag does.
    final isScrubbing = _dragging || widget.previewPosition != null;
    final focused = widget.tvFocused ?? false;

    // The focused bar grows: it has to read as "this is what the arrows move"
    // from across a room.
    final thumbR = focused ? 10.0 : 7.0;
    final trackH = focused ? 6.0 : 3.0;
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
                trackHeight: trackH,
                thumbShape: _TinyThumbShape(thumbRadius: thumbR),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: overlayR),
                activeTrackColor: widget.accentColor,
                inactiveTrackColor: focused ? Colors.white38 : Colors.white24,
                thumbColor: Colors.white,
                overlayColor: widget.accentColor.withAlpha(51),
                secondaryActiveTrackColor: Colors.white38,
              ),
              // On TV the bar is driven by the overlay's own key handling; the
              // Slider must not also claim the arrow keys (its own keyboard
              // step moves the thumb without ever committing a seek).
              child: ExcludeFocus(
                excluding: widget.tvFocused != null,
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
