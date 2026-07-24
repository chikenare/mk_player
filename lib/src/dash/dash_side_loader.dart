import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/foundation.dart';

import 'dash_manifest.dart';
import 'fmp4_webvtt.dart';

/// A selectable DASH subtitle: the source fed to better_player plus, for
/// `wvtt`-in-fMP4 tracks, the manifest track whose segments still need to be
/// downloaded and converted when the user selects it ([lazyTrack]).
class DashSubtitleEntry {
  final BetterPlayerSubtitlesSource source;
  final DashTextTrack? lazyTrack;

  const DashSubtitleEntry(this.source, {this.lazyTrack});
}

/// Track metadata for a DASH source, mapped to better_player types and ready
/// to feed the player: audio tracks for native selection, video tracks for
/// the quality menu and subtitle entries (plain-text ones playable directly,
/// fMP4 ones resolved on demand via [DashSideLoader.loadFmp4Subtitle]).
class DashSideData {
  final List<BetterPlayerAsmsAudioTrack> audioTracks;
  final List<BetterPlayerAsmsTrack> videoTracks;
  final List<DashSubtitleEntry> subtitles;

  const DashSideData({
    this.audioTracks = const [],
    this.videoTracks = const [],
    this.subtitles = const [],
  });
}

/// Fetches and parses a DASH manifest on the Dart side, working around
/// better_player_plus 1.2.x parsing `.mpd` manifests with its HLS parser
/// (which yields no tracks and no subtitles).
///
/// [load] only performs the (retried) manifest fetch, so tracks surface as
/// soon as the MPD parses. `wvtt`-in-fMP4 subtitle segments — potentially
/// hundreds for a long movie — are only downloaded when the user actually
/// selects the track ([loadFmp4Subtitle]), in parallel.
class DashSideLoader {
  const DashSideLoader._();

  static const _requestTimeout = Duration(seconds: 15);
  static const _manifestAttempts = 3;
  static const _segmentConcurrency = 6;

  static final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  static Future<DashSideData?> load(
    String manifestUrl,
    Map<String, String> headers,
  ) async {
    String? data;
    for (var attempt = 0; attempt < _manifestAttempts; attempt++) {
      data = await _getString(manifestUrl, headers);
      if (data != null) break;
      if (attempt < _manifestAttempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 500 << attempt));
      }
    }
    if (data == null) return null;

    final DashManifest manifest;
    try {
      manifest = DashManifest.parse(data, manifestUrl);
    } catch (e) {
      debugPrint('[MkPlayer] DASH manifest parse failed: $e');
      return null;
    }

    final audio = [
      for (final t in manifest.audioTracks)
        BetterPlayerAsmsAudioTrack(
          id: t.groupIndex,
          label: t.label,
          language: t.language,
          mimeType: t.mimeType,
          isDefault: t.isDefault,
        ),
    ];

    final video = [
      for (final t in manifest.videoTracks)
        BetterPlayerAsmsTrack(
          t.id,
          t.width,
          t.height,
          t.bitrate,
          t.frameRate,
          t.codecs,
          t.mimeType,
        ),
    ];

    final subtitles = <DashSubtitleEntry>[];
    for (final track in manifest.textTracks) {
      final entry = _subtitleEntry(track);
      if (entry != null) subtitles.add(entry);
    }

    return DashSideData(
      audioTracks: audio,
      videoTracks: video,
      subtitles: subtitles,
    );
  }

  static DashSubtitleEntry? _subtitleEntry(DashTextTrack track) {
    final name = _subtitleName(track);
    if (track.isPlainText && !track.isFmp4WebVtt) {
      return DashSubtitleEntry(
        BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.network,
          name: name,
          urls: [track.directUrl],
        ),
      );
    }
    if (!track.isFmp4WebVtt) {
      debugPrint('[MkPlayer] Skipping unsupported DASH text track '
          '"$name" (${track.mimeType}/${track.codecs})');
      return null;
    }
    // Placeholder with no content: the controller swaps it for a real memory
    // source once the segments are downloaded and converted on selection.
    return DashSubtitleEntry(
      BetterPlayerSubtitlesSource(
        type: BetterPlayerSubtitlesSourceType.memory,
        name: name,
        content: '',
      ),
      lazyTrack: track,
    );
  }

  /// Downloads and converts a `wvtt`-in-fMP4 [track] into a plain WebVTT
  /// document, fetching up to [_segmentConcurrency] segments at a time.
  /// Returns null when nothing usable could be downloaded.
  static Future<String?> loadFmp4Subtitle(
    DashTextTrack track,
    Map<String, String> headers,
  ) async {
    try {
      final initUrl = track.initializationUrl;
      final init = initUrl != null ? await _getBytes(initUrl, headers) : null;
      final results = await _getAllBytes(track.segmentUrls, headers);
      final segments = results.whereType<Uint8List>().toList();
      if (segments.isEmpty) return null;
      if (segments.length < track.segmentUrls.length) {
        debugPrint('[MkPlayer] DASH subtitle: '
            '${track.segmentUrls.length - segments.length}/'
            '${track.segmentUrls.length} segments failed to download');
      }
      return Fmp4WebVtt.extract(
        initSegment: init ?? Uint8List(0),
        mediaSegments: segments,
      );
    } catch (e) {
      debugPrint('[MkPlayer] DASH subtitle extraction failed: $e');
      return null;
    }
  }

  static String _subtitleName(DashTextTrack track) {
    final base = track.label ?? track.language ?? 'Subtitle';
    if (track.isForced && !base.toLowerCase().contains('forc')) {
      return '$base (forced)';
    }
    return base;
  }

  // ── HTTP ───────────────────────────────────────────────────────────────────

  static Future<String?> _getString(
      String url, Map<String, String> headers) async {
    final bytes = await _getBytes(url, headers);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// Fetches [urls] with a small worker pool, preserving order. Failed
  /// downloads yield null entries.
  static Future<List<Uint8List?>> _getAllBytes(
    List<String> urls,
    Map<String, String> headers,
  ) async {
    final results = List<Uint8List?>.filled(urls.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < urls.length) {
        final i = next++;
        results[i] = await _getBytes(urls[i], headers);
      }
    }

    await Future.wait([
      for (var i = 0; i < _segmentConcurrency && i < urls.length; i++) worker()
    ]);
    return results;
  }

  static Future<Uint8List?> _getBytes(
      String url, Map<String, String> headers) async {
    try {
      return await () async {
        final request = await _httpClient.getUrl(Uri.parse(url));
        headers.forEach(request.headers.add);
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint('[MkPlayer] HTTP ${response.statusCode} for $url');
          return null;
        }
        final builder = BytesBuilder(copy: false);
        await response.forEach(builder.add);
        return builder.takeBytes();
      }()
          .timeout(_requestTimeout);
    } catch (e) {
      debugPrint('[MkPlayer] Request failed for $url: $e');
      return null;
    }
  }
}
