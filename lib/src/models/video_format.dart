/// Container format of a [PlayerSource] stream.
///
/// When set explicitly the native player skips URL-extension inference, which
/// is required for tokenized or extensionless URLs (e.g. signed CDN links
/// where `.mpd`/`.m3u8` is not the last path segment).
enum PlayerVideoFormat {
  /// MPEG-DASH (`.mpd`). Android/ExoPlayer only — iOS AVPlayer does not
  /// support DASH.
  dash,

  /// HLS (`.m3u8`).
  hls,

  /// Smooth Streaming.
  ss,

  /// Progressive media (MP4, MKV, etc.).
  other;

  /// Detects the stream format from a [url], or `null` when it cannot be
  /// determined (progressive media, extensionless URLs).
  ///
  /// Unlike native extension inference — which only looks at the end of the
  /// URL — this scans every path segment, so tokenized CDN links such as
  /// `https://cdn.example.com/manifest.mpd/token/abc123` are still detected.
  /// Query params are ignored on purpose: a `.mpd` inside a signed token must
  /// not misclassify the stream.
  static PlayerVideoFormat? fromUrl(String url) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    for (final segment in path.split('/')) {
      if (segment.endsWith('.mpd')) return dash;
      if (segment.endsWith('.m3u8')) return hls;
      if (segment.endsWith('.ism') || segment.endsWith('.isml')) return ss;
      // Azure Media Services style: manifest(format=mpd-time-csf) /
      // manifest(format=m3u8-aapl).
      if (segment.contains('format=mpd')) return dash;
      if (segment.contains('format=m3u8')) return hls;
    }
    return null;
  }
}
