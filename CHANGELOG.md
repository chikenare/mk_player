## Unreleased

* **Remote control / Android TV.** The built-in controls are now navigable with
  a D-pad: every control is a focus target with a visible ring, the seek bar
  takes focus of its own so ← / → scrub instead of hopping between buttons, and
  OK, Back and the media transport keys (▶⏸ ▶ ⏸ ⏹ ⏪ ⏩ ⏮ ⏭) are wired.
  Holding an arrow accelerates the step (1× → 6× `seekSeconds`) and commits a
  single seek ~400 ms after the last press, previewing the target — thumbnail
  included — on the bar meanwhile. Back closes the controls before it closes
  the player. The settings sheets open with the current entry focused.
* **`PlayerConfig.tvMode`** (`TvMode.auto` by default) decides when that focus
  skin appears: `auto` switches it on at the first key press, `enabled` has it
  on from the first frame (what an Android TV app should pass), `disabled`
  turns key handling off entirely. Touch behaviour is unchanged in every mode.
  On TV the lock button is hidden and the centre buttons leave the focus order.
* **A leanback layout, not just a focusable one.** While the TV skin is on, the
  controls drop what the remote already covers and what a D-pad cannot use
  well: the ◀ back arrow (Back does it), the ⏪ / ⏩ ±`seekSeconds` buttons
  (← / → do it, with acceleration) and **Speed** (`controller.setSpeed` remains
  for a host control). The centre play/pause stays as a state indicator. Touch
  keeps every button, and a `TvMode.auto` build swaps layouts with the input.
* **Audio & subtitles in one side panel on TV.** The two bottom sheets collapse
  into a single **Audio & Subtitles** button that opens a panel pinned to the
  right edge: one column per type, each only as tall as its own tracks, ↑ / ↓
  inside a column and ← / → between them. Focus opens on the track that is
  playing, OK applies it and keeps the panel open so the check mark moves under
  the viewer, and Back closes it. `subtitleActions` sit under the subtitle
  column, below a divider, and still close the panel before running. The touch
  sheets are unchanged.
* **`PlayerConfig.onSkipNext` / `onSkipPrevious`** — the remote's ⏮ / ⏭ keys,
  for hosts with a playlist of their own. Unset, those keys seek.
* **`PlayerConfig.showAspectRatioButton`** — show or hide the Fit → Zoom →
  Stretch button. `null` (default) keeps the previous per-platform rule: shown
  on desktop, web and TV, hidden on mobile where a pinch does the same. Hiding
  it does not lock the fit — `initialVideoFit`, pinch and `setVideoFit` /
  `cycleVideoFit` all still work.
* Focus and selection are drawn in translucent white throughout — the focus
  ring, the selected track and speed chip, and the elapsed time while scrubbing
  ahead. `accentColor` now tints the progress bar only, instead of filling the
  screen with tinted blocks.
* The example app's manifest now declares the leanback launcher and optional
  touchscreen, so it can be installed and driven on an Android TV.

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
