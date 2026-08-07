import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../playback/playback_event.dart';
import 'telemetry_serializer.dart';

/// Persistent FIFO queue of telemetry events.
///
/// Every event is written to disk the moment it is produced, so nothing is lost
/// when the process dies, the device drops off the network, or a TV reboots
/// mid-episode. Events leave the queue **only** when the API accepts them (204)
/// or rejects them permanently (422); everything else is kept for a retry.
///
/// The file is a JSON-lines document, oldest event first. It is rewritten
/// atomically (temp file + rename) on every mutation — the queue is capped at a
/// few hundred small events, so rewriting is cheaper than tracking offsets.
class TelemetryQueue {
  TelemetryQueue({
    required this.maxEvents,
    this.filePath,
    this.verbose = false,
  });

  /// Hard cap; the oldest events are dropped when exceeded.
  final int maxEvents;

  /// Explicit queue file path. Resolved under the app support directory when
  /// null.
  final String? filePath;

  final bool verbose;

  final List<PlaybackEvent> _events = [];
  File? _file;
  bool _loaded = false;
  bool _persistenceDisabled = false;

  // Serialises load/mutate/persist so concurrent enqueues and flushes cannot
  // interleave a read-modify-write.
  Future<void> _lock = Future.value();

  /// Number of events currently queued.
  Future<int> get length => _guard(() async {
        await _ensureLoaded();
        return _events.length;
      });

  /// Appends [event] and persists immediately.
  Future<void> add(PlaybackEvent event) => _guard(() async {
        await _ensureLoaded();
        _events.add(event);
        if (_events.length > maxEvents) {
          final overflow = _events.length - maxEvents;
          _events.removeRange(0, overflow);
          _log('queue full — dropped $overflow oldest event(s)');
        }
        await _persist();
      });

  /// Returns the oldest [count] events without removing them.
  Future<List<PlaybackEvent>> peek(int count) => _guard(() async {
        await _ensureLoaded();
        return _events.take(count).toList(growable: false);
      });

  /// Removes the oldest [count] events (called once the API has accepted or
  /// permanently rejected them).
  Future<void> removeFirst(int count) => _guard(() async {
        await _ensureLoaded();
        if (count <= 0) return;
        _events.removeRange(0, count.clamp(0, _events.length));
        await _persist();
      });

  /// Drops everything. Only for tests and explicit host-app resets.
  Future<void> clear() => _guard(() async {
        await _ensureLoaded();
        _events.clear();
        await _persist();
      });

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<T> _guard<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final file = await _resolveFile();
    if (file == null || !await file.exists()) return;
    try {
      for (final line in await file.readAsLines()) {
        if (line.trim().isEmpty) continue;
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) continue;
        final event = TelemetryEventSerializer.fromJson(decoded);
        if (event != null) _events.add(event);
      }
      _log('restored ${_events.length} event(s) from disk');
    } catch (e) {
      // A truncated write from a killed process must not break playback.
      debugPrint('[MkPlayer] telemetry queue unreadable, starting empty: $e');
      _events.clear();
    }
  }

  Future<File?> _resolveFile() async {
    if (_persistenceDisabled) return null;
    if (_file != null) return _file;
    try {
      final path = filePath;
      if (path != null) {
        _file = File(path);
      } else {
        final dir = Directory(
            '${(await getApplicationSupportDirectory()).path}/mk_player');
        if (!await dir.exists()) await dir.create(recursive: true);
        _file = File('${dir.path}/telemetry_queue.jsonl');
      }
      return _file;
    } catch (e) {
      // No plugin bindings (unit tests) or no writable storage: keep reporting
      // in memory instead of failing the playback session.
      _persistenceDisabled = true;
      debugPrint('[MkPlayer] telemetry persistence unavailable: $e');
      return null;
    }
  }

  Future<void> _persist() async {
    final file = await _resolveFile();
    if (file == null) return;
    final body =
        _events.map((e) => jsonEncode(TelemetryEventSerializer.toJson(e))).join('\n');
    try {
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(body.isEmpty ? '' : '$body\n', flush: true);
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('[MkPlayer] telemetry queue write failed: $e');
    }
  }

  void _log(String message) {
    if (verbose) debugPrint('[MkPlayer] telemetry: $message');
  }
}
