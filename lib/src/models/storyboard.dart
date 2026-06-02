import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// In-memory LRU cache of parsed storyboards, keyed by URL.
const _kMaxCachedStoryboards = 10;
final _storyboardCache = <String, Storyboard>{};
final _storyboardCacheKeys = <String>[];

// ─────────────────────────────────────────────────────────────────────────────
// StoryboardEntry
// ─────────────────────────────────────────────────────────────────────────────

/// One thumbnail entry from a WebVTT storyboard file.
class StoryboardEntry {
  /// Absolute URL to the image (full sprite sheet or individual frame).
  final String imageUrl;

  /// Pixel-space rectangle inside [imageUrl] to display.
  /// `null` = show the whole image (one frame per file).
  final Rect? crop;

  /// Time range this thumbnail represents.
  final Duration start;
  final Duration end;

  const StoryboardEntry({
    required this.imageUrl,
    required this.start,
    required this.end,
    this.crop,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Storyboard
// ─────────────────────────────────────────────────────────────────────────────

/// Parsed WebVTT storyboard used to show thumbnail previews in the scrubber.
///
/// Load with [Storyboard.load]:
/// ```dart
/// final board = await Storyboard.load(
///   'https://cdn.example.com/video/storyboard.vtt',
///   headers: {'Authorization': 'Bearer $token'},
/// );
/// ```
///
/// The VTT format expected:
/// ```
/// WEBVTT
///
/// 00:00:00.000 --> 00:00:05.000
/// https://cdn.example.com/sprites.jpg#xywh=0,0,160,90
///
/// 00:00:05.000 --> 00:00:10.000
/// https://cdn.example.com/sprites.jpg#xywh=160,0,160,90
/// ```
class Storyboard {
  final List<StoryboardEntry> _entries;

  const Storyboard._(this._entries);

  // ── Lookup ─────────────────────────────────────────────────────────────────

  /// Returns the thumbnail entry whose time range contains [position].
  /// Returns the last entry if [position] is past the end.
  ///
  /// Uses binary search — entries are sorted by [StoryboardEntry.start] by the
  /// parser, so this is O(log n) even for multi-hour videos.
  StoryboardEntry? entryAt(Duration position) {
    if (_entries.isEmpty) return null;
    if (position >= _entries.last.end) return _entries.last;

    int lo = 0, hi = _entries.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final e = _entries[mid];
      if (position < e.start) {
        hi = mid - 1;
      } else if (position >= e.end) {
        lo = mid + 1;
      } else {
        return e; // position in [e.start, e.end)
      }
    }
    // Gap between cues (malformed VTT) → closest following entry.
    return lo < _entries.length ? _entries[lo] : _entries.last;
  }

  bool get isEmpty => _entries.isEmpty;
  int get length => _entries.length;

  // ── Factory ────────────────────────────────────────────────────────────────

  /// Fetches and parses a WebVTT storyboard from [url].
  ///
  /// Returns `null` if the network request fails or the body cannot be parsed.
  static Future<Storyboard?> load(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    // Cache hit — move key to most-recently-used position.
    final cached = _storyboardCache[url];
    if (cached != null) {
      _storyboardCacheKeys
        ..remove(url)
        ..add(url);
      return cached;
    }

    try {
      final text = await _fetch(url, headers);
      if (text == null) return null;
      final board = _parse(text, url);

      // Store + evict oldest if over capacity.
      _storyboardCache[url] = board;
      _storyboardCacheKeys.add(url);
      if (_storyboardCacheKeys.length > _kMaxCachedStoryboards) {
        final evict = _storyboardCacheKeys.removeAt(0);
        _storyboardCache.remove(evict);
      }
      return board;
    } catch (e, st) {
      debugPrint('[Storyboard] load error: $e\n$st');
      return null;
    }
  }

  /// Clears the in-memory storyboard cache.
  static void clearCache() {
    _storyboardCache.clear();
    _storyboardCacheKeys.clear();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static Future<String?> _fetch(
    String url,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      headers.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      return await res
          .transform(const Utf8Decoder())
          .join()
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      debugPrint('[Storyboard] fetch timed out: $url');
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Storyboard _parse(String vttText, String sourceUrl) {
    final base = Uri.parse(sourceUrl);
    final entries = <StoryboardEntry>[];

    // Normalise line endings and split.
    final lines = vttText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((l) => l.trim())
        .toList();

    int i = 0;

    // Skip the WEBVTT header block (everything before the first '-->' line).
    while (i < lines.length && !lines[i].contains('-->')) {
      i++;
    }

    while (i < lines.length) {
      final line = lines[i];

      if (!line.contains('-->')) {
        i++;
        continue;
      }

      // ── Timestamp line ─────────────────────────────────────────────────────
      final arrowIdx = line.indexOf('-->');
      final rawStart = line.substring(0, arrowIdx).trim();
      // Strip cue settings that may follow the end timestamp (e.g. align:start).
      final afterArrow = line.substring(arrowIdx + 3).trim();
      final rawEnd = afterArrow.split(' ').first;

      final start = _parseDuration(rawStart);
      final end = _parseDuration(rawEnd);

      i++;

      // ── URL line ───────────────────────────────────────────────────────────
      // Collect all non-empty lines until the next blank line or timestamp.
      String? urlLine;
      while (i < lines.length) {
        final l = lines[i];
        if (l.isEmpty) break;
        if (l.contains('-->')) break;
        urlLine = l;
        i++;
      }

      if (urlLine == null || urlLine.isEmpty) continue;

      // Parse optional sprite-sheet crop fragment: #xywh=x,y,w,h
      String imageUrl;
      Rect? crop;

      final hashIdx = urlLine.indexOf('#xywh=');
      if (hashIdx >= 0) {
        imageUrl = urlLine.substring(0, hashIdx);
        final coords = urlLine.substring(hashIdx + 6).split(',');
        if (coords.length == 4) {
          final x = double.tryParse(coords[0]) ?? 0;
          final y = double.tryParse(coords[1]) ?? 0;
          final w = double.tryParse(coords[2]) ?? 0;
          final h = double.tryParse(coords[3]) ?? 0;
          if (w > 0 && h > 0) crop = Rect.fromLTWH(x, y, w, h);
        }
      } else {
        imageUrl = urlLine;
      }

      // Resolve relative URLs against the VTT source URL.
      if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://')) {
        imageUrl = base.resolve(imageUrl).toString();
      }

      entries.add(StoryboardEntry(
        imageUrl: imageUrl,
        start: start,
        end: end,
        crop: crop,
      ));
    }

    return Storyboard._(entries);
  }

  /// Parses `HH:MM:SS.mmm`, `MM:SS.mmm`, `HH:MM:SS`, or `MM:SS`.
  static Duration _parseDuration(String s) {
    try {
      final parts = s.split(':');
      int h = 0, m = 0;
      double sec = 0;
      if (parts.length == 3) {
        h = int.parse(parts[0]);
        m = int.parse(parts[1]);
        sec = double.parse(parts[2]);
      } else if (parts.length == 2) {
        m = int.parse(parts[0]);
        sec = double.parse(parts[1]);
      }
      final ms = ((h * 3600 + m * 60 + sec) * 1000).round();
      return Duration(milliseconds: ms);
    } catch (_) {
      return Duration.zero;
    }
  }
}
