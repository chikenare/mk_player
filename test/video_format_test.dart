import 'package:flutter_test/flutter_test.dart';
import 'package:mk_player/mk_player.dart';

void main() {
  group('PlayerVideoFormat.fromUrl', () {
    test('detects manifest by trailing extension', () {
      expect(
        PlayerVideoFormat.fromUrl('https://cdn.example.com/video/manifest.mpd'),
        PlayerVideoFormat.dash,
      );
      expect(
        PlayerVideoFormat.fromUrl('https://cdn.example.com/live/master.m3u8'),
        PlayerVideoFormat.hls,
      );
      expect(
        PlayerVideoFormat.fromUrl('https://ms.example.com/video.ism/manifest'),
        PlayerVideoFormat.ss,
      );
    });

    test('detects manifest in a middle segment of tokenized URLs', () {
      expect(
        PlayerVideoFormat.fromUrl(
            'https://cdn.example.com/manifest.mpd/token/sig123'),
        PlayerVideoFormat.dash,
      );
      expect(
        PlayerVideoFormat.fromUrl(
            'https://cdn.example.com/playlist.m3u8/segment/key=xyz'),
        PlayerVideoFormat.hls,
      );
    });

    test('detects Azure Media Services manifest(format=...) URLs', () {
      expect(
        PlayerVideoFormat.fromUrl(
            'https://azure.example.com/x/manifest(format=mpd-time-csf)'),
        PlayerVideoFormat.dash,
      );
      expect(
        PlayerVideoFormat.fromUrl(
            'https://azure.example.com/x/manifest(format=m3u8-aapl)'),
        PlayerVideoFormat.hls,
      );
    });

    test('is case-insensitive', () {
      expect(
        PlayerVideoFormat.fromUrl('https://cdn.example.com/UPPER/MANIFEST.MPD'),
        PlayerVideoFormat.dash,
      );
    });

    test('ignores extensions inside query params', () {
      expect(
        PlayerVideoFormat.fromUrl(
            'https://cdn.example.com/opaque/abc123?sig=.mpd'),
        isNull,
      );
      expect(
        PlayerVideoFormat.fromUrl(
            'https://cdn.example.com/live/master.m3u8?token=abc.mpd'),
        PlayerVideoFormat.hls,
      );
    });

    test('returns null for progressive or opaque URLs', () {
      expect(
        PlayerVideoFormat.fromUrl('https://cdn.example.com/video.mp4'),
        isNull,
      );
      expect(
        PlayerVideoFormat.fromUrl('https://cdn.example.com/opaque/abc123'),
        isNull,
      );
    });
  });
}
