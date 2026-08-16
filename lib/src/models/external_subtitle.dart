/// An external subtitle track supplied by the host app, in addition to any
/// subtitles already embedded in the media.
///
/// Provide these via [PlayerSource.externalSubtitles]. They appear in the
/// subtitle selector alongside the embedded tracks. Selecting one loads it
/// through `better_player` as a network subtitle (SRT, WebVTT, …).
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
///
/// When the list comes from your own API as JSON, fetch it in the host app and
/// map it with [ExternalSubtitle.listFromJson]:
///
/// ```dart
/// final res = await http.get(
///   Uri.parse('https://api.example.com/videos/123/subtitles'),
///   headers: {'Authorization': 'Bearer $token'},
/// );
/// final subs = ExternalSubtitle.listFromJson(jsonDecode(res.body) as List);
/// PlayerSource.network(videoUrl, externalSubtitles: subs);
/// ```
class ExternalSubtitle {
  /// HTTP(S) URL or absolute file path to the subtitle file.
  ///
  /// Anything that does not start with `http://` or `https://` is treated as a
  /// local file path and read from disk instead of being downloaded.
  final String uri;

  /// Display label shown in the subtitle selector. Falls back to [language]
  /// or the URI basename when null.
  final String? title;

  /// Optional language code (e.g. `en`, `es`).
  final String? language;

  /// HTTP headers sent when downloading [uri]. Ignored for local files.
  ///
  /// Not inherited from the video source: subtitles frequently live on a
  /// different host, where the video's `Authorization`/`Referer` headers would
  /// be rejected. Pass them explicitly when the subtitle endpoint needs auth.
  final Map<String, String> headers;

  /// Select this track as soon as the source is opened.
  ///
  /// When no external subtitle sets this, the player starts with subtitles off
  /// (the "Off" entry) and the user picks one from the subtitle sheet.
  final bool selectedByDefault;

  const ExternalSubtitle({
    required this.uri,
    this.title,
    this.language,
    this.headers = const {},
    this.selectedByDefault = false,
  });

  /// True when [uri] points at a local file rather than a network resource.
  bool get isLocal =>
      !uri.startsWith('http://') && !uri.startsWith('https://');

  /// Builds a list from a `label → uri` map, e.g.
  /// `{ 'English': 'https://…/en.vtt', 'Español': 'https://…/es.vtt' }`.
  ///
  /// [headers] are applied to every entry; set [selectFirst] to start playback
  /// with the first track already enabled.
  static List<ExternalSubtitle> fromMap(
    Map<String, String> labelToUri, {
    Map<String, String> headers = const {},
    bool selectFirst = false,
  }) {
    return labelToUri.entries.indexed
        .map(
          (e) => ExternalSubtitle(
            uri: e.$2.value,
            title: e.$2.key,
            headers: headers,
            selectedByDefault: selectFirst && e.$1 == 0,
          ),
        )
        .toList();
  }

  /// Creates an [ExternalSubtitle] from a decoded JSON object.
  ///
  /// Expects `{ "url": "...", "title": "...", "language": "..." }`. The `uri`
  /// key is also accepted as an alias for `url`. Throws [FormatException] if no
  /// subtitle URL is present (it is required).
  factory ExternalSubtitle.fromJson(Map<String, dynamic> json) {
    final uri = (json['url'] ?? json['uri']) as String?;
    if (uri == null || uri.isEmpty) {
      throw const FormatException(
        'ExternalSubtitle.fromJson: missing "url"/"uri" field',
      );
    }
    return ExternalSubtitle(
      uri: uri,
      title: json['title'] as String?,
      language: json['language'] as String?,
    );
  }

  /// Maps a decoded JSON array (e.g. an API response) to a list of subtitles.
  ///
  /// Entries that are not objects or lack a URL are skipped, so one malformed
  /// item never discards the whole list.
  static List<ExternalSubtitle> listFromJson(List<dynamic> jsonList) {
    final result = <ExternalSubtitle>[];
    for (final item in jsonList) {
      if (item is! Map<String, dynamic>) continue;
      try {
        result.add(ExternalSubtitle.fromJson(item));
      } on FormatException {
        // Skip invalid entries.
      }
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is ExternalSubtitle &&
      other.uri == uri &&
      other.title == title &&
      other.language == language &&
      other.selectedByDefault == selectedByDefault;

  @override
  int get hashCode => Object.hash(uri, title, language, selectedByDefault);
}
