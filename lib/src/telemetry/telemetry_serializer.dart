import '../playback/playback_event.dart';

/// Wire format of the telemetry API: the one place that knows how a
/// [PlaybackEvent] is written for `POST {apiUrl}` and read back from the
/// on-disk queue.
///
/// Everything the backend is strict about lives here rather than in the
/// measurement layer — the caps it applies to every counter, the `episodeId`
/// floor, the shape of a session id, the timestamp format. A different
/// backend means a different serialiser, not a different player.
abstract final class TelemetryEventSerializer {
  /// Serialises [event] for the API.
  ///
  /// Two rules the server is strict about are enforced here rather than trusted
  /// upstream: **no numeric key is ever sent as `null`** (an absent key defaults
  /// to 0 server-side, an explicit null is a 422), and every value is clamped to
  /// the accepted range, so a bogus reading can never reject a whole batch.
  ///
  /// The queue persists events through this same method, so what is written to
  /// disk is already clamped.
  static Map<String, dynamic> toJson(PlaybackEvent event) => {
        'type': event.type.name,
        'sessionId': event.sessionId,
        'occurredAt': iso8601WithOffset(event.occurredAt, event.utcOffset),
        'contentId': event.contentId,
        if (event.episodeId != null && event.episodeId! >= 1)
          'episodeId': event.episodeId,
        'positionSeconds': _clamp(event.positionSeconds, 360000),
        'secondsWatchedDelta': _clamp(event.secondsWatchedDelta, 300),
        if (event.bytesDownloadedDelta != null)
          'bytesDownloadedDelta':
              _clamp(event.bytesDownloadedDelta!, 5000000000),
        'stallCountDelta': _clamp(event.stallCountDelta, 1000),
        'stalledSecondsDelta': _clamp(event.stalledSecondsDelta, 300),
        if (event.startupMs != null) 'startupMs': _clamp(event.startupMs!, 600000),
        if (event.resolution != null)
          'resolution': event.resolution!.length <= 16
              ? event.resolution
              : event.resolution!.substring(0, 16),
      };

  /// Rebuilds an event persisted by [toJson], or null when the payload is
  /// unusable for the API.
  static PlaybackEvent? fromJson(Map<String, dynamic> json) {
    PlaybackEventType? type;
    for (final t in PlaybackEventType.values) {
      if (t.name == json['type']) type = t;
    }
    final occurredAt = DateTime.tryParse('${json['occurredAt']}');
    final contentId = json['contentId'];
    final sessionId = json['sessionId'];
    if (type == null ||
        occurredAt == null ||
        contentId is! int ||
        contentId < 1 ||
        sessionId is! String ||
        !sessionIdPattern.hasMatch(sessionId)) {
      // Unusable for the API (including events queued by an older build with a
      // different shape): dropping them beats poisoning every future batch.
      return null;
    }
    return PlaybackEvent(
      type: type,
      sessionId: sessionId,
      occurredAt: occurredAt,
      utcOffset: _offsetOf('${json['occurredAt']}'),
      contentId: contentId,
      episodeId: json['episodeId'] as int?,
      positionSeconds: json['positionSeconds'] as int? ?? 0,
      secondsWatchedDelta: json['secondsWatchedDelta'] as int? ?? 0,
      bytesDownloadedDelta: json['bytesDownloadedDelta'] as int?,
      stallCountDelta: json['stallCountDelta'] as int? ?? 0,
      stalledSecondsDelta: json['stalledSecondsDelta'] as int? ?? 0,
      startupMs: json['startupMs'] as int?,
      resolution: json['resolution'] as String?,
    );
  }

  static int _clamp(int value, int max) =>
      value < 0 ? 0 : (value > max ? max : value);
}

/// Session ids the API accepts: 8–64 chars of `[0-9A-Za-z_-]`.
final RegExp sessionIdPattern = RegExp(r'^[0-9A-Za-z_-]{8,64}$');

/// ISO 8601 timestamp that always carries an offset (`Z` or `±HH:MM`).
///
/// `DateTime.toIso8601String()` emits a bare local timestamp with no zone,
/// which the API rejects with 422. The server files the consumption under this
/// date, so an offline queue flushed the next day is still counted on the day
/// it was watched.
///
/// [offset] overrides the zone to render the instant in; without it a UTC
/// value renders as `Z` and a local one with the device's current offset.
String iso8601WithOffset(DateTime time, [Duration? offset]) {
  final effective =
      offset ?? (time.isUtc ? Duration.zero : time.timeZoneOffset);
  if (effective == Duration.zero) return time.toUtc().toIso8601String();

  final wallClock = time.toUtc().add(effective).toIso8601String();
  final sign = effective.isNegative ? '-' : '+';
  final minutes = effective.inMinutes.abs();
  final hh = (minutes ~/ 60).toString().padLeft(2, '0');
  final mm = (minutes % 60).toString().padLeft(2, '0');
  // Drop the 'Z' the shifted value carries and state the real offset instead.
  return '${wallClock.substring(0, wallClock.length - 1)}$sign$hh:$mm';
}

/// Reads the `±HH:MM` / `Z` suffix of an ISO 8601 timestamp.
Duration? _offsetOf(String iso) {
  if (iso.endsWith('Z') || iso.endsWith('z')) return Duration.zero;
  final match = RegExp(r'([+-])(\d{2}):?(\d{2})$').firstMatch(iso);
  if (match == null) return null;
  final duration = Duration(
    hours: int.parse(match.group(2)!),
    minutes: int.parse(match.group(3)!),
  );
  return match.group(1) == '-' ? -duration : duration;
}
