import 'package:flutter/material.dart';

import '../models/storyboard.dart';
import 'progress_bar.dart' show formatDuration;

// Image-size cache: avoid re-resolving the same sprite sheet on every rebuild.
final _sizeCache = <String, Size>{};

// ─────────────────────────────────────────────────────────────────────────────
// ThumbnailPreview — popup shown above the scrubber while dragging
// ─────────────────────────────────────────────────────────────────────────────

class ThumbnailPreview extends StatelessWidget {
  final StoryboardEntry? entry;
  final Duration position;

  /// Display width of the thumbnail image. Height is derived from the crop
  /// aspect ratio (falls back to 16:9 when no crop is available).
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
    final imgH = e?.crop != null
        ? width * e!.crop!.height / e.crop!.width
        : width * 9 / 16;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Thumbnail frame ──────────────────────────────────────────────────
        Container(
          width: width,
          height: imgH,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          clipBehavior: Clip.hardEdge,
          child: e != null
              ? _SpriteImage(entry: e, width: width)
              : const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.white24,
                    size: 20,
                  ),
                ),
        ),

        // ── Time label ───────────────────────────────────────────────────────
        const SizedBox(height: 5),
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
// _SpriteImage — renders a cropped region of a sprite sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SpriteImage extends StatefulWidget {
  final StoryboardEntry entry;
  final double width;

  const _SpriteImage({required this.entry, required this.width});

  @override
  State<_SpriteImage> createState() => _SpriteImageState();
}

class _SpriteImageState extends State<_SpriteImage> {
  Size? _spriteSize;

  @override
  void initState() {
    super.initState();
    final url = widget.entry.imageUrl;
    if (_sizeCache.containsKey(url)) {
      _spriteSize = _sizeCache[url];
    } else {
      _resolveSize(url);
    }
  }

  @override
  void didUpdateWidget(_SpriteImage old) {
    super.didUpdateWidget(old);
    if (old.entry.imageUrl != widget.entry.imageUrl) {
      final url = widget.entry.imageUrl;
      if (_sizeCache.containsKey(url)) {
        setState(() => _spriteSize = _sizeCache[url]);
      } else {
        setState(() => _spriteSize = null);
        _resolveSize(url);
      }
    }
  }

  void _resolveSize(String url) {
    final provider = NetworkImage(url);
    final stream = provider.resolve(const ImageConfiguration());
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
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final crop = widget.entry.crop;

    // No crop info → show full image (individual frame per cue).
    if (crop == null) {
      return Image.network(
        widget.entry.imageUrl,
        width: widget.width,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _ErrorPlaceholder(),
      );
    }

    final spriteW = _spriteSize?.width;

    // While the sprite size resolves, show a placeholder the same size as
    // the thumbnail will be.
    if (spriteW == null) {
      return SizedBox(
        width: widget.width,
        height: widget.width * crop.height / crop.width,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        ),
      );
    }

    // Scale the sprite sheet so that the crop fills [widget.width] horizontally.
    final scale = widget.width / crop.width;
    final renderW = spriteW * scale;

    return SizedBox(
      width: widget.width,
      height: crop.height * scale,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.translate(
          offset: Offset(-crop.left * scale, -crop.top * scale),
          child: Image.network(
            widget.entry.imageUrl,
            width: renderW,
            fit: BoxFit.fitWidth,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const _ErrorPlaceholder(),
          ),
        ),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: Colors.white24,
        size: 20,
      ),
    );
  }
}
