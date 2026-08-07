/// Playback telemetry event types accepted by `POST /api/telemetry`.
enum TelemetryEventType {
  /// First frame of a playback session. Carries `startupMs`, every delta zero.
  start,

  /// Emitted every 30 seconds **while playing**.
  progress,

  /// Playback stopped, the source changed, or the app is going away.
  end,

  /// Fatal player error. Carries the pending deltas, never the error detail
  /// (that belongs in Sentry — this API only records that the session ended
  /// badly).
  error;

  String get wireName => name;
}

/// A single telemetry event, exactly as it is serialised into the `events`
/// array of the API payload.
///
/// **Every counter is a delta since the previous event of the same session**,
/// never an accumulated total: if one report is lost, a single interval is
/// lost with it and nothing else.
class TelemetryEvent {
  final TelemetryEventType type;

  /// Groups every event of one playback. Generated per media load and repeated
  /// on all of that session's events, which is what lets the server rebuild a
  /// session and deduplicate a queue that was sent twice.
  ///
  /// Must match [sessionIdPattern] — the API rejects anything else.
  final String sessionId;

  /// When the event happened. Serialised as ISO 8601 **with offset**; the
  /// server files the consumption under this date, so an offline queue flushed
  /// the next day is still counted on the right day.
  final DateTime occurredAt;

  /// UTC offset [occurredAt] was captured at.
  ///
  /// Null means "use the offset of [occurredAt] itself" (`Z` for a UTC value,
  /// the device offset for a local one). It is filled in when an event is read
  /// back from the queue so that a report sent days later still carries the
  /// offset the device had when the video was watched, not the one it has now.
  final Duration? utcOffset;

  final int contentId;

  /// `null` for movies.
  final int? episodeId;

  /// Playhead position when the event was emitted.
  final int positionSeconds;

  /// Seconds actually played since the previous event (server cap: 300).
  final int secondsWatchedDelta;

  /// Bytes that really crossed the network since the previous event (server
  /// cap: 5e9). `null` when the platform cannot report it — never estimated
  /// from the bitrate. See [TelemetryConfig.bytesLoadedProvider].
  final int? bytesDownloadedDelta;

  /// Rebuffers since the previous event.
  final int stallCountDelta;

  /// Seconds frozen since the previous event (server cap: 300).
  final int stalledSecondsDelta;

  /// Only on [TelemetryEventType.start]: play → first frame, in milliseconds.
  final int? startupMs;

  /// Height of the quality being watched, e.g. `"1080"`.
  final String? resolution;

  const TelemetryEvent({
    required this.type,
    required this.sessionId,
    required this.occurredAt,
    this.utcOffset,
    required this.contentId,
    this.episodeId,
    required this.positionSeconds,
    this.secondsWatchedDelta = 0,
    this.bytesDownloadedDelta,
    this.stallCountDelta = 0,
    this.stalledSecondsDelta = 0,
    this.startupMs,
    this.resolution,
  });

  /// Serialises the event for the API.
  ///
  /// Two rules the server is strict about are enforced here rather than trusted
  /// upstream: **no numeric key is ever sent as `null`** (an absent key defaults
  /// to 0 server-side, an explicit null is a 422), and every value is clamped to
  /// the accepted range, so a bogus reading can never reject a whole batch.
  Map<String, dynamic> toJson() => {
        'type': type.wireName,
        'sessionId': sessionId,
        'occurredAt': iso8601WithOffset(occurredAt, utcOffset),
        'contentId': contentId,
        if (episodeId != null && episodeId! >= 1) 'episodeId': episodeId,
        'positionSeconds': _clamp(positionSeconds, 360000),
        'secondsWatchedDelta': _clamp(secondsWatchedDelta, 300),
        if (bytesDownloadedDelta != null)
          'bytesDownloadedDelta': _clamp(bytesDownloadedDelta!, 5000000000),
        'stallCountDelta': _clamp(stallCountDelta, 1000),
        'stalledSecondsDelta': _clamp(stalledSecondsDelta, 300),
        if (startupMs != null) 'startupMs': _clamp(startupMs!, 600000),
        if (resolution != null)
          'resolution': resolution!.length <= 16
              ? resolution
              : resolution!.substring(0, 16),
      };

  static int _clamp(int value, int max) =>
      value < 0 ? 0 : (value > max ? max : value);

  static TelemetryEvent? fromJson(Map<String, dynamic> json) {
    TelemetryEventType? type;
    for (final t in TelemetryEventType.values) {
      if (t.wireName == json['type']) type = t;
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
    return TelemetryEvent(
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

  @override
  String toString() => 'TelemetryEvent(${type.wireName}, session $sessionId, '
      'content $contentId, pos=${positionSeconds}s, '
      'watched=${secondsWatchedDelta}s, stalls=$stallCountDelta)';
}

/// Session ids the API accepts: 8–64 chars of `[0-9A-Za-z_-]`.
final RegExp sessionIdPattern = RegExp(r'^[0-9A-Za-z_-]{8,64}$');

/// ISO 8601 timestamp that always carries an offset (`Z` or `±HH:MM`).
///
/// `DateTime.toIso8601String()` emits a bare local timestamp with no zone,
/// which the API rejects with 422.
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
