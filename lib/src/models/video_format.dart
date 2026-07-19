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
  other,
}
