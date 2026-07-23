import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/foundation.dart';

import 'dash_manifest.dart';
import 'fmp4_webvtt.dart';

/// Track metadata for a DASH source, mapped to better_player types and ready
/// to feed the player: audio tracks for native selection, video tracks for
/// the quality menu and subtitles as directly renderable sources.
class DashSideData {
  final List<BetterPlayerAsmsAudioTrack> audioTracks;
  final List<BetterPlayerAsmsTrack> videoTracks;
  final List<BetterPlayerSubtitlesSource> subtitles;

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
/// `wvtt`-in-fMP4 subtitle tracks are downloaded and converted to plain
/// WebVTT held in memory; plain-text tracks are passed through as network
/// sources.
class DashSideLoader {
  const DashSideLoader._();

  static final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  static Future<DashSideData?> load(
    String manifestUrl,
    Map<String, String> headers,
  ) async {
    final data = await _getString(manifestUrl, headers);
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

    final subtitles = <BetterPlayerSubtitlesSource>[];
    for (final track in manifest.textTracks) {
      final source = await _loadTextTrack(track, headers);
      if (source != null) subtitles.add(source);
    }

    return DashSideData(
      audioTracks: audio,
      videoTracks: video,
      subtitles: subtitles,
    );
  }

  static Future<BetterPlayerSubtitlesSource?> _loadTextTrack(
    DashTextTrack track,
    Map<String, String> headers,
  ) async {
    final name = _subtitleName(track);
    if (track.isPlainText && !track.isFmp4WebVtt) {
      return BetterPlayerSubtitlesSource(
        type: BetterPlayerSubtitlesSourceType.network,
        name: name,
        urls: [track.directUrl],
      );
    }
    if (!track.isFmp4WebVtt) {
      debugPrint('[MkPlayer] Skipping unsupported DASH text track '
          '"$name" (${track.mimeType}/${track.codecs})');
      return null;
    }

    try {
      final initUrl = track.initializationUrl;
      final init =
          initUrl != null ? await _getBytes(initUrl, headers) : null;
      final segments = <Uint8List>[];
      for (final url in track.segmentUrls) {
        final bytes = await _getBytes(url, headers);
        if (bytes != null) segments.add(bytes);
      }
      if (segments.isEmpty) return null;

      final vtt = Fmp4WebVtt.extract(
        initSegment: init ?? Uint8List(0),
        mediaSegments: segments,
      );
      if (vtt == null) return null;
      return BetterPlayerSubtitlesSource(
        type: BetterPlayerSubtitlesSourceType.memory,
        name: name,
        content: vtt,
      );
    } catch (e) {
      debugPrint('[MkPlayer] DASH subtitle extraction failed for "$name": $e');
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

  static Future<Uint8List?> _getBytes(
      String url, Map<String, String> headers) async {
    try {
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
    } catch (e) {
      debugPrint('[MkPlayer] Request failed for $url: $e');
      return null;
    }
  }
}
