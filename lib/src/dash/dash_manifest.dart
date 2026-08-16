import 'package:xml/xml.dart';

/// Audio track advertised in a DASH manifest.
///
/// [groupIndex] is the ordinal of the AdaptationSet among *audio* sets, which
/// matches the ExoPlayer track-group index used by the native
/// `setAudioTrack(label, index)` selection.
class DashAudioTrack {
  final int groupIndex;
  final String? label;
  final String? language;
  final String? mimeType;
  final bool isDefault;

  const DashAudioTrack({
    required this.groupIndex,
    this.label,
    this.language,
    this.mimeType,
    this.isDefault = false,
  });
}

/// Video quality (representation) advertised in a DASH manifest.
class DashVideoTrack {
  final String? id;
  final int width;
  final int height;
  final int bitrate;
  final int frameRate;
  final String? codecs;
  final String? mimeType;

  const DashVideoTrack({
    this.id,
    required this.width,
    required this.height,
    required this.bitrate,
    this.frameRate = 0,
    this.codecs,
    this.mimeType,
  });
}

/// Subtitle track advertised in a DASH manifest.
///
/// Two delivery shapes are supported:
///  * a single plain-text file ([directUrl], e.g. sidecar `.vtt`), and
///  * segmented WebVTT-in-fMP4 (`wvtt` codec: [initializationUrl] +
///    [segmentUrls] pointing to `.m4s` fragments).
class DashTextTrack {
  final String? label;
  final String? language;
  final bool isForced;
  final String? mimeType;
  final String? codecs;
  final String? directUrl;
  final String? initializationUrl;
  final List<String> segmentUrls;

  const DashTextTrack({
    this.label,
    this.language,
    this.isForced = false,
    this.mimeType,
    this.codecs,
    this.directUrl,
    this.initializationUrl,
    this.segmentUrls = const [],
  });

  /// WebVTT boxed inside fragmented MP4 segments — needs binary extraction
  /// before better_player's text-based subtitle parser can render it.
  bool get isFmp4WebVtt =>
      (codecs?.toLowerCase().contains('wvtt') ?? false) &&
      (initializationUrl != null || segmentUrls.isNotEmpty);

  /// Plain text subtitle addressable as a single URL (`text/vtt`, `.srt`…).
  bool get isPlainText => directUrl != null;
}

/// Track metadata parsed from a DASH MPD manifest.
///
/// better_player's own MPD parser only reads representations that declare a
/// `BaseURL`, so SegmentTemplate streams expose no audio tracks, qualities or
/// embedded subtitles. This parser recovers that metadata on the Dart side.
///
/// Only the first `Period` is inspected. `SegmentTemplate` (with
/// `SegmentTimeline` or `duration`) and single-file `BaseURL` addressing are
/// supported; `SegmentList`/`SegmentBase` text tracks are skipped.
class DashManifest {
  final List<DashAudioTrack> audioTracks;
  final List<DashVideoTrack> videoTracks;
  final List<DashTextTrack> textTracks;

  const DashManifest({
    this.audioTracks = const [],
    this.videoTracks = const [],
    this.textTracks = const [],
  });

  static DashManifest parse(String data, String manifestUrl) {
    final document = XmlDocument.parse(data);
    final mpd = document.rootElement;

    var base = Uri.parse(manifestUrl);
    base = _resolveBaseUrl(base, mpd);

    final periodDuration = _parseIsoDuration(
      _firstElement(mpd, 'Period')?.getAttribute('duration') ??
          mpd.getAttribute('mediaPresentationDuration'),
    );

    final period = _firstElement(mpd, 'Period');
    if (period == null) return const DashManifest();
    final periodBase = _resolveBaseUrl(base, period);

    final audio = <DashAudioTrack>[];
    final video = <DashVideoTrack>[];
    final text = <DashTextTrack>[];

    for (final set in _elements(period, 'AdaptationSet')) {
      switch (_contentTypeOf(set)) {
        case 'audio':
          audio.add(_parseAudio(set, groupIndex: audio.length));
        case 'video':
          video.addAll(_parseVideo(set));
        case 'text':
          final track = _parseText(set, _resolveBaseUrl(periodBase, set),
              periodDuration: periodDuration);
          if (track != null) text.add(track);
        default:
          break;
      }
    }

    return DashManifest(
      audioTracks: audio,
      videoTracks: video,
      textTracks: text,
    );
  }

  // ── AdaptationSet parsing ──────────────────────────────────────────────────

  static DashAudioTrack _parseAudio(XmlElement set,
      {required int groupIndex}) {
    final language = set.getAttribute('lang');
    return DashAudioTrack(
      groupIndex: groupIndex,
      label: _labelOf(set) ?? language,
      language: language,
      mimeType: _mimeTypeOf(set),
      isDefault: _rolesOf(set).contains('main'),
    );
  }

  static Iterable<DashVideoTrack> _parseVideo(XmlElement set) sync* {
    for (final rep in _elements(set, 'Representation')) {
      final width = int.tryParse(rep.getAttribute('width') ?? '') ?? 0;
      final height = int.tryParse(rep.getAttribute('height') ?? '') ?? 0;
      final bitrate = int.tryParse(rep.getAttribute('bandwidth') ?? '') ?? 0;
      if (width == 0 && height == 0 && bitrate == 0) continue;
      yield DashVideoTrack(
        id: rep.getAttribute('id'),
        width: width,
        height: height,
        bitrate: bitrate,
        frameRate: _parseFrameRate(
            rep.getAttribute('frameRate') ?? set.getAttribute('frameRate')),
        codecs: rep.getAttribute('codecs') ?? set.getAttribute('codecs'),
        mimeType: _mimeTypeOf(set) ?? rep.getAttribute('mimeType'),
      );
    }
  }

  static DashTextTrack? _parseText(XmlElement set, Uri base,
      {double? periodDuration}) {
    final rep = _firstElement(set, 'Representation');
    if (rep == null) return null;
    final repBase = _resolveBaseUrl(base, rep);

    final language = set.getAttribute('lang');
    final mimeType = _mimeTypeOf(set) ?? rep.getAttribute('mimeType');
    final codecs = rep.getAttribute('codecs') ?? set.getAttribute('codecs');
    final roles = _rolesOf(set);
    final label = _labelOf(set) ?? language;
    final isForced =
        roles.contains('forced-subtitle') || roles.contains('forced_subtitle');

    final template = _firstElement(rep, 'SegmentTemplate') ??
        _firstElement(set, 'SegmentTemplate');
    if (template != null) {
      final segments = _expandTemplate(template, rep, repBase,
          periodDuration: periodDuration);
      if (segments == null) return null;
      return DashTextTrack(
        label: label,
        language: language,
        isForced: isForced,
        mimeType: mimeType,
        codecs: codecs,
        initializationUrl: segments.initializationUrl,
        segmentUrls: segments.mediaUrls,
      );
    }

    // Single-file addressing: the Representation's own BaseURL is the file.
    final fileUrl = _firstElement(rep, 'BaseURL')?.innerText.trim();
    if (fileUrl != null && fileUrl.isNotEmpty) {
      return DashTextTrack(
        label: label,
        language: language,
        isForced: isForced,
        mimeType: mimeType,
        codecs: codecs,
        directUrl: base.resolve(fileUrl).toString(),
      );
    }
    return null; // SegmentList/SegmentBase text tracks are not supported.
  }

  // ── SegmentTemplate expansion ──────────────────────────────────────────────

  static ({String? initializationUrl, List<String> mediaUrls})?
      _expandTemplate(XmlElement template, XmlElement rep, Uri base,
          {double? periodDuration}) {
    final media = template.getAttribute('media');
    if (media == null) return null;
    final repId = rep.getAttribute('id') ?? '';
    final bandwidth = rep.getAttribute('bandwidth') ?? '';
    final startNumber =
        int.tryParse(template.getAttribute('startNumber') ?? '') ?? 1;
    final timescale =
        int.tryParse(template.getAttribute('timescale') ?? '') ?? 1;

    String? initUrl;
    final initialization = template.getAttribute('initialization');
    if (initialization != null) {
      initUrl = base
          .resolve(_substitute(initialization,
              representationId: repId, bandwidth: bandwidth))
          .toString();
    }

    // (startTime, duration) pairs in timescale units, one per segment.
    final timeline = <(int, int)>[];
    final segmentTimeline = _firstElement(template, 'SegmentTimeline');
    if (segmentTimeline != null) {
      var time = 0;
      for (final s in _elements(segmentTimeline, 'S')) {
        time = int.tryParse(s.getAttribute('t') ?? '') ?? time;
        final d = int.tryParse(s.getAttribute('d') ?? '') ?? 0;
        if (d <= 0) return null;
        var repeat = int.tryParse(s.getAttribute('r') ?? '') ?? 0;
        if (repeat < 0) {
          // r="-1": repeat until the end of the period.
          if (periodDuration == null) return null;
          repeat = ((periodDuration * timescale - time) / d).ceil() - 1;
        }
        for (var i = 0; i <= repeat; i++) {
          timeline.add((time, d));
          time += d;
        }
      }
    } else {
      final d = int.tryParse(template.getAttribute('duration') ?? '') ?? 0;
      if (d <= 0 || periodDuration == null) return null;
      final count = (periodDuration * timescale / d).ceil();
      for (var i = 0; i < count; i++) {
        timeline.add((i * d, d));
      }
    }

    final urls = <String>[];
    for (var i = 0; i < timeline.length; i++) {
      urls.add(base
          .resolve(_substitute(
            media,
            representationId: repId,
            bandwidth: bandwidth,
            number: startNumber + i,
            time: timeline[i].$1,
          ))
          .toString());
    }
    return (initializationUrl: initUrl, mediaUrls: urls);
  }

  /// Substitutes `$RepresentationID$` / `$Number$` / `$Time$` / `$Bandwidth$`
  /// template identifiers, honouring `%0Nd` width formatting and `$$` escapes.
  static String _substitute(
    String template, {
    required String representationId,
    required String bandwidth,
    int? number,
    int? time,
  }) {
    final pattern =
        RegExp(r'\$(RepresentationID|Number|Time|Bandwidth)?(%0(\d+)d)?\$');
    return template.replaceAllMapped(pattern, (m) {
      final id = m.group(1);
      if (id == null) return r'$'; // "$$" escape
      final width = int.tryParse(m.group(3) ?? '') ?? 0;
      final value = switch (id) {
        'RepresentationID' => representationId,
        'Bandwidth' => bandwidth,
        'Number' => number?.toString() ?? '',
        'Time' => time?.toString() ?? '',
        _ => '',
      };
      return value.padLeft(width, '0');
    });
  }

  // ── XML helpers (namespace-agnostic) ───────────────────────────────────────

  static Iterable<XmlElement> _elements(XmlElement parent, String localName) =>
      parent.childElements.where((e) => e.name.local == localName);

  static XmlElement? _firstElement(XmlElement parent, String localName) {
    for (final e in parent.childElements) {
      if (e.name.local == localName) return e;
    }
    return null;
  }

  static Uri _resolveBaseUrl(Uri current, XmlElement element) {
    final baseUrl = _firstElement(element, 'BaseURL')?.innerText.trim();
    if (baseUrl == null || baseUrl.isEmpty) return current;
    return current.resolve(baseUrl);
  }

  static String? _labelOf(XmlElement set) {
    final label = _firstElement(set, 'Label')?.innerText.trim();
    return (label == null || label.isEmpty) ? null : label;
  }

  static String? _mimeTypeOf(XmlElement set) =>
      set.getAttribute('mimeType') ??
      _firstElement(set, 'Representation')?.getAttribute('mimeType');

  static Set<String> _rolesOf(XmlElement set) => _elements(set, 'Role')
      .map((r) => r.getAttribute('value') ?? '')
      .where((v) => v.isNotEmpty)
      .toSet();

  static String _contentTypeOf(XmlElement set) {
    final contentType = set.getAttribute('contentType');
    if (contentType != null && contentType.isNotEmpty) return contentType;
    final mime = _mimeTypeOf(set) ?? '';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
    if (mime.startsWith('text/') || mime == 'application/ttml+xml') {
      return 'text';
    }
    if (mime == 'application/mp4') {
      final codecs = (_firstElement(set, 'Representation')
                  ?.getAttribute('codecs') ??
              set.getAttribute('codecs') ??
              '')
          .toLowerCase();
      if (codecs.contains('wvtt') || codecs.contains('stpp')) return 'text';
    }
    return '';
  }

  static int _parseFrameRate(String? value) {
    if (value == null || value.isEmpty) return 0;
    final parts = value.split('/');
    final num = double.tryParse(parts[0]) ?? 0;
    if (parts.length == 1) return num.round();
    final den = double.tryParse(parts[1]) ?? 1;
    return den == 0 ? 0 : (num / den).round();
  }

  /// Parses an ISO-8601 duration (`PT1H2M3.5S`) into seconds.
  static double? _parseIsoDuration(String? value) {
    if (value == null) return null;
    final m = RegExp(
            r'^PT(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?$')
        .firstMatch(value.trim());
    if (m == null) return null;
    final h = double.tryParse(m.group(1) ?? '') ?? 0;
    final min = double.tryParse(m.group(2) ?? '') ?? 0;
    final s = double.tryParse(m.group(3) ?? '') ?? 0;
    final total = h * 3600 + min * 60 + s;
    return total > 0 ? total : null;
  }
}
