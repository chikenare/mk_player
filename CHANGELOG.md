## Unreleased

* **`PlayerConfig.onPlaybackEvent`** — a neutral callback that receives every
  playback event the player measures (`start` / `progress` / `end` / `error`),
  so a host app can report to its own API without the built-in HTTP reporter.
  It needs no `TelemetryConfig`; with both configured, one measurement feeds
  both and each event arrives at each side once and identical. As always, a
  source without `contentId` produces no events at all — the callback included.
* Split measurement from transport. `lib/src/playback/` now holds the
  measurement layer (`PlaybackSessionTracker` and its `PlaybackEvent` records):
  session ids, deltas, seek discarding, stalls, the `progress` cadence and the
  lifecycle observer, with no queue, network or disk. `lib/src/telemetry/`
  keeps what is specific to the built-in API — config, queue, client, reporter,
  and the new `telemetry_serializer.dart`, which is now the only place that
  knows the wire format (payload keys, value caps, `sessionId` shape, timestamp
  format). `TelemetryReporter` became a sink of the tracker.
* `TelemetryEvent` was renamed to `PlaybackEvent` and `TelemetryEventType` to
  `PlaybackEventType`; both old names remain exported as aliases, so existing
  code keeps compiling. `TelemetryEvent.toJson`/`fromJson` moved to
  `TelemetryEventSerializer` — the only breaking point, and only for code that
  serialised events by hand.
* No change for apps that pass `telemetry:`: `TelemetryConfig`,
  `TelemetryReporter`, `CustomPlayerController.telemetry` and
  `updateTelemetryToken` keep their API and their behaviour.

## 0.0.1

* TODO: Describe initial release.
