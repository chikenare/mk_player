import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mk_player/src/dash/dash_manifest.dart';

void main() {
  const manifestUrl = 'https://cdn.test/base/stream.mpd';
  late DashManifest manifest;

  setUpAll(() {
    final data = File('test/fixtures/shaka_av1.mpd').readAsStringSync();
    manifest = DashManifest.parse(data, manifestUrl);
  });

  group('DashManifest.parse (shaka packager fixture)', () {
    test('finds both audio tracks with labels and languages', () {
      expect(manifest.audioTracks, hasLength(2));
      final es = manifest.audioTracks[0];
      final ko = manifest.audioTracks[1];
      expect(es.groupIndex, 0);
      expect(es.label, 'es');
      expect(es.language, 'es');
      expect(ko.groupIndex, 1);
      expect(ko.label, 'ko');
      expect(ko.language, 'ko');
    });

    test('finds both video qualities', () {
      expect(manifest.videoTracks, hasLength(2));
      expect(manifest.videoTracks[0].width, 1920);
      expect(manifest.videoTracks[0].height, 1080);
      expect(manifest.videoTracks[0].bitrate, 14741605);
      expect(manifest.videoTracks[0].frameRate, 24);
      expect(manifest.videoTracks[1].height, 720);
    });

    test('finds all four text tracks with roles', () {
      expect(manifest.textTracks, hasLength(4));
      expect(manifest.textTracks[0].label, 'es');
      expect(manifest.textTracks[0].isForced, isTrue);
      expect(manifest.textTracks[1].label, 'es (2)');
      expect(manifest.textTracks[1].isForced, isFalse);
      expect(manifest.textTracks[3].label, 'English [ForcedNarrative]');
      expect(manifest.textTracks[3].isForced, isTrue);
      expect(manifest.textTracks[3].language, 'en');
    });

    test('text tracks are wvtt-in-fMP4 with resolved segment URLs', () {
      final track = manifest.textTracks[1]; // "es (2)"
      expect(track.isFmp4WebVtt, isTrue);
      expect(
        track.initializationUrl,
        'https://cdn.test/base/01KY6GPPXXA4B5YD7HZY6H70S1/init.mp4',
      );
      // One S entry, r absent → a single media segment, $Number$ from 1.
      expect(track.segmentUrls,
          ['https://cdn.test/base/01KY6GPPXXA4B5YD7HZY6H70S1/1.m4s']);
    });
  });

  group('SegmentTemplate expansion', () {
    test('expands repeats, \$Number\$ padding and \$Time\$', () {
      const mpd = '''
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" mediaPresentationDuration="PT30S">
  <Period>
    <AdaptationSet contentType="text" lang="en">
      <Representation id="sub1" bandwidth="100" codecs="wvtt" mimeType="application/mp4">
        <SegmentTemplate timescale="1000" startNumber="5"
            initialization="\$RepresentationID\$/init.mp4"
            media="\$RepresentationID\$/seg-\$Number%03d\$-\$Time\$.m4s">
          <SegmentTimeline>
            <S t="0" d="10000" r="2"/>
          </SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';
      final m = DashManifest.parse(mpd, 'https://cdn.test/x/master.mpd');
      final track = m.textTracks.single;
      expect(track.initializationUrl, 'https://cdn.test/x/sub1/init.mp4');
      expect(track.segmentUrls, [
        'https://cdn.test/x/sub1/seg-005-0.m4s',
        'https://cdn.test/x/sub1/seg-006-10000.m4s',
        'https://cdn.test/x/sub1/seg-007-20000.m4s',
      ]);
    });

    test('supports single-file text/vtt tracks via BaseURL', () {
      const mpd = '''
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011">
  <Period>
    <AdaptationSet contentType="text" lang="fr">
      <Label>Français</Label>
      <Representation id="s" bandwidth="10" mimeType="text/vtt">
        <BaseURL>subs/french.vtt</BaseURL>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';
      final m = DashManifest.parse(mpd, 'https://cdn.test/x/master.mpd');
      final track = m.textTracks.single;
      expect(track.isPlainText, isTrue);
      expect(track.isFmp4WebVtt, isFalse);
      expect(track.directUrl, 'https://cdn.test/x/subs/french.vtt');
      expect(track.label, 'Français');
    });
  });
}
