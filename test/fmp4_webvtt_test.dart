import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mk_player/src/dash/fmp4_webvtt.dart';

void main() {
  test('extracts WebVTT cues from a real shaka wvtt fMP4 track', () {
    final init =
        File('test/fixtures/sub_es2_init.mp4').readAsBytesSync();
    final segment =
        File('test/fixtures/sub_es2_1.m4s').readAsBytesSync();

    final vtt = Fmp4WebVtt.extract(
      initSegment: init,
      mediaSegments: [segment],
    );

    expect(vtt, isNotNull);
    expect(vtt, startsWith('WEBVTT'));

    final cuePattern = RegExp(
        r'(\d{2}):(\d{2}):(\d{2})\.(\d{3}) --> (\d{2}):(\d{2}):(\d{2})\.(\d{3})');
    final matches = cuePattern.allMatches(vtt!).toList();
    // The track spans ~64 minutes of dialogue; expect a substantial cue count.
    expect(matches.length, greaterThan(100));

    // Timestamps must be well-formed and strictly ordered start < end.
    for (final m in matches) {
      final start = int.parse(m.group(1)!) * 3600000 +
          int.parse(m.group(2)!) * 60000 +
          int.parse(m.group(3)!) * 1000 +
          int.parse(m.group(4)!);
      final end = int.parse(m.group(5)!) * 3600000 +
          int.parse(m.group(6)!) * 60000 +
          int.parse(m.group(7)!) * 1000 +
          int.parse(m.group(8)!);
      expect(end, greaterThan(start));
    }

    // Cue payloads must contain visible text between timing lines.
    final blocks = vtt.split('\n\n').where((b) => b.contains('-->'));
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      expect(lines.length, greaterThanOrEqualTo(2),
          reason: 'cue without payload: $block');
    }
  });
}
