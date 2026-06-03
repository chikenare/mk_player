import 'dart:math';

import 'package:flutter/material.dart';

import '../models/storyboard.dart';
import 'progress_bar.dart' show formatDuration;

// Image-size cache: avoid re-resolving the same sprite sheet on every rebuild.
final _sizeCache = <String, Size>{};

// Fixed thumbnail aspect ratio (horizontal). Storyboard crops can be narrow or
// oddly shaped; we always render into a 16:9 frame and cover it.
const double _kThumbAspect = 16 / 9;

// ─────────────────────────────────────────────────────────────────────────────
// ThumbnailPreview — popup shown above the scrubber while dragging
// ─────────────────────────────────────────────────────────────────────────────

class ThumbnailPreview extends StatelessWidget {
  final StoryboardEntry? entry;
  final Duration position;

  /// Display width of the thumbnail image. Height is fixed to a 16:9 ratio.
  final double width;

  const ThumbnailPreview({
    super.key,
    required this.entry,
    required this.position,
    this.width = 144,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final height = width / _kThumbAspect;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Thumbnail frame ──────────────────────────────────────────────────
        // Only rendered when there is an entry; the frame hides itself if the
        // image fails to load (no broken-image placeholder).
        if (e != null) ...[
          _ThumbFrame(entry: e, width: width, height: height),
          const SizedBox(height: 5),
        ],

        // ── Time label ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            formatDuration(position),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ThumbFrame — bordered 16:9 frame that renders a (cropped) sprite region.
// Collapses to nothing if the image is missing or fails to load.
// ─────────────────────────────────────────────────────────────────────────────

class _ThumbFrame extends StatefulWidget {
  final StoryboardEntry entry;
  final double width;
  final double height;

  const _ThumbFrame({
    required this.entry,
    required this.width,
    required this.height,
  });

  @override
  State<_ThumbFrame> createState() => _ThumbFrameState();
}

class _ThumbFrameState extends State<_ThumbFrame> {
  Size? _spriteSize;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolveForEntry();
  }

  @override
  void didUpdateWidget(_ThumbFrame old) {
    super.didUpdateWidget(old);
    if (old.entry.imageUrl != widget.entry.imageUrl) {
      _failed = false;
      _spriteSize = null;
      _resolveForEntry();
    }
  }

  // Sprite-sheet crops need the source dimensions to compute the cover scale;
  // single-frame images (no crop) don't.
  void _resolveForEntry() {
    if (widget.entry.crop == null) return;
    final url = widget.entry.imageUrl;
    final cached = _sizeCache[url];
    if (cached != null) {
      _spriteSize = cached;
      return;
    }
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        final s = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        _sizeCache[url] = s;
        if (mounted) setState(() => _spriteSize = s);
      },
      onError: (_, _) {
        stream.removeListener(listener);
        if (mounted) setState(() => _failed = true);
      },
    );
    stream.addListener(listener);
  }

  void _markFailed() {
    if (_failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      clipBehavior: Clip.hardEdge,
      child: _buildImage(),
    );
  }

  Widget _buildImage() {
    final crop = widget.entry.crop;

    // No crop info → a single full frame per cue; cover the 16:9 box.
    if (crop == null) {
      return Image.network(
        widget.entry.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          _markFailed();
          return const SizedBox.shrink();
        },
      );
    }

    final spriteSize = _spriteSize;
    if (spriteSize == null) {
      // Still resolving the sprite-sheet dimensions.
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }

    // Scale the sprite so the crop region COVERS the fixed 16:9 box, then
    // centre it (overflow is clipped by the parent Container).
    final scale = max(widget.width / crop.width, widget.height / crop.height);
    final renderW = spriteSize.width * scale;
    final dx = -crop.left * scale - (crop.width * scale - widget.width) / 2;
    final dy = -crop.top * scale - (crop.height * scale - widget.height) / 2;

    return OverflowBox(
      alignment: Alignment.topLeft,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Image.network(
          widget.entry.imageUrl,
          width: renderW,
          fit: BoxFit.fitWidth,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) {
            _markFailed();
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
