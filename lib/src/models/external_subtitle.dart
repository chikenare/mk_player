/// An external subtitle track supplied by the host app, in addition to any
/// subtitles already embedded in the media.
///
/// Provide these via [PlayerSource.externalSubtitles]. They appear in the
/// subtitle selector alongside the embedded tracks. Selecting one loads it
/// through `media_kit` as a URI subtitle (SRT, WebVTT, ASS, …).
///
/// ```dart
/// PlayerSource.network(
///   'https://cdn.example.com/video.m3u8',
///   externalSubtitles: const [
///     ExternalSubtitle(
///       uri: 'https://cdn.example.com/subs/en.vtt',
///       title: 'English',
///       language: 'en',
///     ),
///     ExternalSubtitle(
///       uri: 'https://cdn.example.com/subs/es.vtt',
///       title: 'Español',
///       language: 'es',
///     ),
///   ],
/// )
/// ```
class ExternalSubtitle {
  /// HTTP(S) URL or absolute file path to the subtitle file.
  final String uri;

  /// Display label shown in the subtitle selector. Falls back to [language]
  /// or the URI basename when null.
  final String? title;

  /// Optional language code (e.g. `en`, `es`).
  final String? language;

  const ExternalSubtitle({
    required this.uri,
    this.title,
    this.language,
  });

  /// Builds a list from a `label → uri` map, e.g.
  /// `{ 'English': 'https://…/en.vtt', 'Español': 'https://…/es.vtt' }`.
  static List<ExternalSubtitle> fromMap(Map<String, String> labelToUri) {
    return labelToUri.entries
        .map((e) => ExternalSubtitle(uri: e.value, title: e.key))
        .toList();
  }

  @override
  bool operator ==(Object other) =>
      other is ExternalSubtitle &&
      other.uri == uri &&
      other.title == title &&
      other.language == language;

  @override
  int get hashCode => Object.hash(uri, title, language);
}
