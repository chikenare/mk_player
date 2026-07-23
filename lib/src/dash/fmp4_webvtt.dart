import 'dart:convert';
import 'dart:typed_data';

/// Extracts WebVTT cues from CMAF/DASH `wvtt` subtitle tracks (ISO-14496-30
/// WebVTT-in-fMP4) and rebuilds a plain-text WebVTT document that
/// better_player's text-based subtitle parser can render.
///
/// Sample timing comes from `tfdt` + `trun`; cue payloads come from `vttc`
/// (`payl` + optional `sttg`) boxes inside `mdat`. `vtte` (empty-cue) samples
/// are skipped. Cues split across consecutive samples are merged back into a
/// single cue.
class Fmp4WebVtt {
  const Fmp4WebVtt._();

  /// Returns a WebVTT document, or null when no cues could be extracted.
  static String? extract({
    required Uint8List initSegment,
    required List<Uint8List> mediaSegments,
    int fallbackTimescale = 1000,
  }) {
    final timescale = _readTimescale(initSegment) ?? fallbackTimescale;
    final cues = <_Cue>[];

    for (final segment in mediaSegments) {
      _extractSegment(segment, timescale, cues);
    }
    if (cues.isEmpty) return null;

    cues.sort((a, b) => a.start.compareTo(b.start));
    final merged = _mergeSplitCues(cues);

    final buffer = StringBuffer('WEBVTT\n\n');
    for (final cue in merged) {
      buffer.write(_formatTime(cue.start));
      buffer.write(' --> ');
      buffer.write(_formatTime(cue.end));
      if (cue.settings.isNotEmpty) buffer.write(' ${cue.settings}');
      buffer.writeln();
      buffer.writeln(cue.text);
      buffer.writeln();
    }
    return buffer.toString();
  }

  // ── Segment walking ────────────────────────────────────────────────────────

  static void _extractSegment(
      Uint8List data, int timescale, List<_Cue> cues) {
    for (final moof in _boxes(data, 0, data.length)) {
      if (moof.type != 'moof') continue;
      for (final traf in _boxes(data, moof.dataStart, moof.end)) {
        if (traf.type != 'traf') continue;
        _extractTraf(data, moof, traf, timescale, cues);
      }
    }
  }

  static void _extractTraf(Uint8List data, _Box moof, _Box traf,
      int timescale, List<_Cue> cues) {
    final bytes = ByteData.sublistView(data);

    int? defaultSampleDuration;
    int? defaultSampleSize;
    int? baseDataOffset;
    var baseTime = 0;
    final truns = <_Box>[];

    for (final box in _boxes(data, traf.dataStart, traf.end)) {
      switch (box.type) {
        case 'tfhd':
          final flags = bytes.getUint32(box.dataStart) & 0xFFFFFF;
          var pos = box.dataStart + 4 + 4; // version/flags + track_ID
          if (flags & 0x1 != 0) {
            baseDataOffset = bytes.getUint64(pos);
            pos += 8;
          }
          if (flags & 0x2 != 0) pos += 4; // sample_description_index
          if (flags & 0x8 != 0) {
            defaultSampleDuration = bytes.getUint32(pos);
            pos += 4;
          }
          if (flags & 0x10 != 0) {
            defaultSampleSize = bytes.getUint32(pos);
            pos += 4;
          }
        case 'tfdt':
          final version = bytes.getUint8(box.dataStart);
          baseTime = version == 1
              ? bytes.getUint64(box.dataStart + 4)
              : bytes.getUint32(box.dataStart + 4);
        case 'trun':
          truns.add(box);
      }
    }

    var time = baseTime;
    for (final trun in truns) {
      final flags = bytes.getUint32(trun.dataStart) & 0xFFFFFF;
      final sampleCount = bytes.getUint32(trun.dataStart + 4);
      var pos = trun.dataStart + 8;

      // Sample data location: trun data-offset is relative to the moof start
      // (default-base-is-moof, the CMAF profile); an explicit tfhd
      // base-data-offset overrides that base.
      var dataPos = baseDataOffset ?? moof.start;
      if (flags & 0x1 != 0) {
        dataPos += bytes.getInt32(pos);
        pos += 4;
      } else {
        // No data-offset: assume payload starts at the mdat right after moof.
        final mdat = _boxes(data, moof.end, data.length)
            .where((b) => b.type == 'mdat')
            .firstOrNull;
        if (mdat == null) return;
        dataPos = mdat.dataStart;
      }
      if (flags & 0x4 != 0) pos += 4; // first_sample_flags

      for (var i = 0; i < sampleCount; i++) {
        var duration = defaultSampleDuration ?? 0;
        var size = defaultSampleSize ?? 0;
        if (flags & 0x100 != 0) {
          duration = bytes.getUint32(pos);
          pos += 4;
        }
        if (flags & 0x200 != 0) {
          size = bytes.getUint32(pos);
          pos += 4;
        }
        if (flags & 0x400 != 0) pos += 4; // sample_flags
        if (flags & 0x800 != 0) pos += 4; // sample_composition_time_offset

        if (size <= 0 || dataPos + size > data.length) return;
        _extractSample(data, dataPos, dataPos + size,
            startSec: time / timescale,
            endSec: (time + duration) / timescale,
            cues: cues);
        dataPos += size;
        time += duration;
      }
    }
  }

  /// A sample holds `vttc` (cue) and/or `vtte` (no cue on screen) boxes.
  static void _extractSample(Uint8List data, int start, int end,
      {required double startSec,
      required double endSec,
      required List<_Cue> cues}) {
    for (final box in _boxes(data, start, end)) {
      if (box.type != 'vttc') continue;
      String? text;
      var settings = '';
      for (final child in _boxes(data, box.dataStart, box.end)) {
        if (child.type == 'payl') {
          text = _utf8Of(data, child.dataStart, child.end);
        } else if (child.type == 'sttg') {
          settings = _utf8Of(data, child.dataStart, child.end);
        }
      }
      if (text != null && text.trim().isNotEmpty) {
        cues.add(_Cue(startSec, endSec, settings.trim(), text.trimRight()));
      }
    }
  }

  // ── Box iteration ──────────────────────────────────────────────────────────

  static Iterable<_Box> _boxes(Uint8List data, int start, int end) sync* {
    final bytes = ByteData.sublistView(data);
    var pos = start;
    while (pos + 8 <= end) {
      var size = bytes.getUint32(pos);
      final type = latin1.decode(data.sublist(pos + 4, pos + 8));
      var dataStart = pos + 8;
      if (size == 1) {
        if (pos + 16 > end) return;
        size = bytes.getUint64(pos + 8);
        dataStart = pos + 16;
      } else if (size == 0) {
        size = end - pos;
      }
      if (size < 8 || pos + size > end) return;
      yield _Box(type, pos, dataStart, pos + size);
      pos += size;
    }
  }

  /// `moov → trak → mdia → mdhd` timescale from the init segment.
  static int? _readTimescale(Uint8List init) {
    final bytes = ByteData.sublistView(init);
    final moov =
        _boxes(init, 0, init.length).where((b) => b.type == 'moov').firstOrNull;
    if (moov == null) return null;
    for (final trak in _boxes(init, moov.dataStart, moov.end)) {
      if (trak.type != 'trak') continue;
      for (final mdia in _boxes(init, trak.dataStart, trak.end)) {
        if (mdia.type != 'mdia') continue;
        for (final mdhd in _boxes(init, mdia.dataStart, mdia.end)) {
          if (mdhd.type != 'mdhd') continue;
          final version = bytes.getUint8(mdhd.dataStart);
          final offset = version == 1 ? 4 + 16 : 4 + 8;
          return bytes.getUint32(mdhd.dataStart + offset);
        }
      }
    }
    return null;
  }

  // ── Cue assembly ───────────────────────────────────────────────────────────

  /// ISO-14496-30 splits cues at sample boundaries; contiguous samples with an
  /// identical payload are the same on-screen cue and are merged back.
  static List<_Cue> _mergeSplitCues(List<_Cue> cues) {
    const epsilon = 0.05;
    final merged = <_Cue>[];
    for (final cue in cues) {
      final last = merged.lastWhere(
        (c) =>
            c.text == cue.text &&
            c.settings == cue.settings &&
            (cue.start - c.end).abs() < epsilon,
        orElse: () => _Cue.none,
      );
      if (identical(last, _Cue.none)) {
        merged.add(_Cue(cue.start, cue.end, cue.settings, cue.text));
      } else {
        last.end = cue.end;
      }
    }
    return merged;
  }

  static String _utf8Of(Uint8List data, int start, int end) {
    var e = end;
    while (e > start && data[e - 1] == 0) {
      e--; // some packagers null-terminate payloads
    }
    return utf8.decode(data.sublist(start, e), allowMalformed: true);
  }

  static String _formatTime(double seconds) {
    final totalMs = (seconds * 1000).round();
    final h = totalMs ~/ 3600000;
    final m = (totalMs % 3600000) ~/ 60000;
    final s = (totalMs % 60000) ~/ 1000;
    final ms = totalMs % 1000;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}.${ms.toString().padLeft(3, '0')}';
  }
}

class _Cue {
  final double start;
  double end;
  final String settings;
  final String text;

  _Cue(this.start, this.end, this.settings, this.text);

  static final none = _Cue(-1, -1, '', '');
}

class _Box {
  final String type;
  final int start;
  final int dataStart;
  final int end;

  const _Box(this.type, this.start, this.dataStart, this.end);
}
