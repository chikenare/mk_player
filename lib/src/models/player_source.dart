import 'external_subtitle.dart';
import 'video_format.dart';

/// Describes a single playable media source.
///
/// Supports network streams (HTTP/HTTPS, HLS `.m3u8`, DASH `.mpd`) and local
/// file paths. Provide [headers] for any protected URL that requires auth.
class PlayerSource {
  /// Network URL (HTTP, HTTPS, HLS, DASH).
  final String? url;

  /// Absolute path to a local file.
  final String? path;

  /// Optional HTTP request headers injected at the native layer.
  final Map<String, String> headers;

  /// Human-readable title shown in the top bar during playback.
  final String? title;

  /// Start playback at this position instead of the beginning.
  ///
  /// The seek is applied after the first `playing` event fires, so it works
  /// reliably with both progressive and adaptive (HLS/DASH) streams.
  final Duration? startAt;

  /// Container format of the stream.
  ///
  /// When `null` the format is auto-detected from the URL path extension
  /// (`.mpd` → DASH, `.m3u8` → HLS). Set it explicitly for URLs where the
  /// extension is missing or not the last path segment (signed CDN links,
  /// proxied URLs, etc.), since native inference would otherwise fail.
  final PlayerVideoFormat? format;

  /// Whether this source is a live stream.
  ///
  /// When `true`, the player shows a red LIVE badge and disables the scrubber.
  /// Defaults to `false` — set it explicitly for live HLS/DASH feeds. The
  /// player does not auto-detect liveness (duration can be reported late for
  /// VOD, which would cause false positives).
  final bool isLive;

  /// URL of a poster/thumbnail image shown while the video is loading.
  ///
  /// Accepts:
  ///   - Network URL: `https://cdn.example.com/poster.jpg`
  ///   - Asset path: `assets/images/poster.png`
  ///   - Absolute file path: `/storage/emulated/0/thumb.jpg`
  ///
  /// The poster fades out once the first video frame is decoded.
  final String? posterUrl;

  // ── Storyboard (thumbnail scrubber) ───────────────────────────────────────

  /// URL of a WebVTT storyboard file used to show thumbnail previews
  /// while scrubbing. Typically a `.vtt` file that references sprite sheets.
  final String? storyboardUrl;

  /// HTTP headers sent when fetching [storyboardUrl].
  final Map<String, String> storyboardHeaders;

  /// Extra subtitle tracks supplied by the host app, shown in the selector
  /// alongside any subtitles embedded in the media itself.
  final List<ExternalSubtitle> externalSubtitles;

  const PlayerSource.network(
    String this.url, {
    this.headers = const {},
    this.title,
    this.format,
    this.startAt,
    this.isLive = false,
    this.posterUrl,
    this.storyboardUrl,
    this.storyboardHeaders = const {},
    this.externalSubtitles = const [],
  }) : path = null;

  const PlayerSource.file(
    String this.path, {
    this.title,
    this.startAt,
    this.isLive = false,
    this.posterUrl,
    this.storyboardUrl,
    this.storyboardHeaders = const {},
    this.externalSubtitles = const [],
  })  : url = null,
        format = null,
        headers = const {};

  bool get isLocal => path != null;
  bool get isNetwork => url != null;

  @override
  String toString() => 'PlayerSource(${isLocal ? path : url})';
}
