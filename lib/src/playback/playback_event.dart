/// What a [PlaybackEvent] records about a playback session.
enum PlaybackEventType {
  /// First frame of a playback session. Carries `startupMs`, every delta zero.
  start,

  /// Emitted periodically **while playing** (every 30s by default).
  progress,

  /// Playback stopped, the source changed, or the app is going away.
  end,

  /// Fatal player error. Carries the pending deltas, never the error detail
  /// (that belongs in crash reporting — this record only says the session
  /// ended badly).
  error,
}

/// One measurement taken during a playback session.
///
/// This is a plain record of what the player did: it knows nothing about any
/// API, wire format or transport. Serialising it for a backend is the job of
/// that backend's layer (see `TelemetryEventSerializer` for the built-in one).
///
/// **Every counter is a delta since the previous event of the same session**,
/// never an accumulated total: if one report is lost, a single interval is
/// lost with it and nothing else.
class PlaybackEvent {
  final PlaybackEventType type;

  /// Groups every event of one playback. Generated per media load and repeated
  /// on all of that session's events, which is what lets a consumer rebuild a
  /// session and deduplicate a batch that was delivered twice.
  final String sessionId;

  /// When the event happened, on the device clock.
  final DateTime occurredAt;

  /// UTC offset [occurredAt] was captured at.
  ///
  /// Null means "use the offset of [occurredAt] itself" (`Z` for a UTC value,
  /// the device offset for a local one). It is filled in when an event is read
  /// back from a persisted queue so that a report delivered days later still
  /// carries the offset the device had when the video was watched, not the one
  /// it has now.
  final Duration? utcOffset;

  /// Identifier of what was being played, taken from `PlayerSource.contentId`.
  /// A source without one is never measured, so this is always set.
  final int contentId;

  /// `null` for movies.
  final int? episodeId;

  /// Playhead position when the event was emitted.
  final int positionSeconds;

  /// Seconds actually played since the previous event.
  final int secondsWatchedDelta;

  /// Bytes that really crossed the network since the previous event. `null`
  /// when the platform cannot report it — never estimated from the bitrate.
  /// See `PlaybackSessionOptions.bytesLoadedProvider`.
  final int? bytesDownloadedDelta;

  /// Rebuffers since the previous event.
  final int stallCountDelta;

  /// Seconds frozen since the previous event.
  final int stalledSecondsDelta;

  /// Only on [PlaybackEventType.start]: play → first frame, in milliseconds.
  final int? startupMs;

  /// Height of the quality being watched, e.g. `"1080"`.
  final String? resolution;

  const PlaybackEvent({
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

  @override
  String toString() => 'PlaybackEvent(${type.name}, session $sessionId, '
      'content $contentId, pos=${positionSeconds}s, '
      'watched=${secondsWatchedDelta}s, stalls=$stallCountDelta)';
}

/// Former name of [PlaybackEvent], kept so existing host apps keep compiling.
typedef TelemetryEvent = PlaybackEvent;

/// Former name of [PlaybackEventType], kept so existing host apps keep
/// compiling.
typedef TelemetryEventType = PlaybackEventType;
