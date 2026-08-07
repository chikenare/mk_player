# mk_player

A self-contained, highly reusable Flutter video player built on [better_player_plus](https://pub.dev/packages/better_player_plus) (ExoPlayer on Android). Drop it into any app and get a premium streaming experience with zero boilerplate.

> **Platform support:** Android only.

---

## Features

| | |
|---|---|
| **Formats** | HLS `.m3u8`, DASH `.mpd`, progressive HTTP/HTTPS, local files |
| **Auth** | Custom HTTP headers per source (`Authorization`, `Cookie`, `User-Agent`, …) |
| **Tracks** | Dynamic audio, subtitle and video-quality switching |
| **Controls** | Play/pause, seek, volume, mute, speed (0.25×–4×), double-tap ±10 s |
| **Android TV** | Full D-pad / remote navigation: focusable controls with a focus ring, arrow-key scrubbing with acceleration, media transport keys, back-hides-controls, and a leanback chrome that drops the touch-only buttons in favour of a side-panel track picker |
| **Thumbnails** | WebVTT storyboard scrubber preview with sprite sheet support |
| **Fullscreen** | Landscape orientation lock + immersive SystemChrome |
| **Wakelock** | Screen stays on during playback, released on pause/error/dispose |
| **Error UI** | User-friendly overlay with Retry button and automatic 30 s timeout |
| **PiP** | Built-in Picture-in-Picture button (Android & iOS) plus lifecycle hooks |
| **Telemetry** | Playback reporting to your API — watched time, startup, rebuffers, quality — with a persistent offline queue |
| **State** | `ChangeNotifier` — no third-party state library required |

---

## Requirements

| Platform | Minimum version |
|---|---|
| Android | SDK 21 |
| Flutter | 3.41 |
| Dart | 3.11 |

---

## Installation

### 1. Add the dependency

**From pub.dev** (once published):
```yaml
dependencies:
  mk_player: ^1.0.0
```

**From a local path** (monorepo / side-by-side):
```yaml
dependencies:
  mk_player:
    path: ../mk_player
```

Run:
```bash
flutter pub get
```

### 2. Platform setup

#### Android — `android/app/build.gradle`
```groovy
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

For HTTP (non-HTTPS) streams, allow cleartext traffic in
`android/app/src/main/AndroidManifest.xml`:

```xml
<application
    android:usesCleartextTraffic="true"
    ...>
```

#### Android TV setup

The player needs nothing extra to answer a remote — but the app does need to be
installable on a TV and to reach the leanback launcher. In
`android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
    <!-- Both optional, so the same APK still installs on phones -->
    <uses-feature
        android:name="android.hardware.touchscreen"
        android:required="false"/>
    <uses-feature
        android:name="android.software.leanback"
        android:required="false"/>

    <application
        android:banner="@drawable/tv_banner"  <!-- 320×180, required by Play -->
        ...>
        <activity ...>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
```

Then pass `tvMode: TvMode.enabled` in your `PlayerConfig` — see
[Remote control / Android TV](#remote-control--android-tv) for the full key map.

---

## Initialisation

No special player initialisation is required — just the standard Flutter binding
call before `runApp`:

```dart
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}
```

---

## Quick start

```dart
import 'package:mk_player/mk_player.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final CustomPlayerController _controller;

  @override
  void initState() {
    super.initState();

    _controller = CustomPlayerController(
      config: const PlayerConfig(autoPlay: true),
    );

    _controller.open(
      PlayerSource.network('https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8'),
    );
  }

  @override
  void dispose() {
    _controller.dispose(); // always dispose — prevents memory leaks
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PlayerView(controller: _controller),
    );
  }
}
```

---

## PlayerSource

Each source is created with a named constructor:

```dart
// Network stream (HLS, DASH, progressive)
PlayerSource.network('https://cdn.example.com/master.m3u8')

// Local file
PlayerSource.file('/storage/emulated/0/Movies/video.mp4')
```

### All parameters

```dart
PlayerSource.network(
  'https://cdn.example.com/master.m3u8',

  // Title shown in the player's top bar.
  title: 'Episode 3 — The Finale',

  // Start playback at a position instead of the beginning (resume support).
  startAt: const Duration(minutes: 12, seconds: 30),

  // Mark as a live stream → shows a LIVE badge and disables the scrubber.
  isLive: false,

  // Poster/preview image shown while loading. Accepts network URL,
  // asset path ('assets/…'), or absolute file path.
  posterUrl: 'https://cdn.example.com/poster.jpg',

  // HTTP headers forwarded to the native ExoPlayer layer.
  // Works for HLS segment requests, DASH manifests, and progressive downloads.
  headers: {
    'Authorization': 'Bearer $accessToken',
    'User-Agent': 'MyApp/2.0',
    'Cookie': 'session=$sessionId',
  },

  // WebVTT storyboard for thumbnail scrubber previews.
  storyboardUrl: 'https://cdn.example.com/storyboard.vtt',

  // Headers for the storyboard request (if it's also protected).
  storyboardHeaders: {'Authorization': 'Bearer $accessToken'},

  // External subtitles shown alongside the embedded ones (SRT, VTT, ASS…).
  externalSubtitles: const [
    ExternalSubtitle(uri: 'https://cdn.example.com/en.vtt', title: 'English', language: 'en'),
    ExternalSubtitle(uri: 'https://cdn.example.com/es.vtt', title: 'Español', language: 'es'),
  ],

  // Telemetry identity — see [Telemetry](#telemetry).
  contentId: 812,       // required to report this playback
  episodeId: 4711,      // null for movies
)
```

### Playlist

```dart
await _controller.openPlaylist([
  PlayerSource.network('https://cdn.example.com/ep1.m3u8', title: 'Episode 1'),
  PlayerSource.network('https://cdn.example.com/ep2.m3u8', title: 'Episode 2'),
]);
```

---

## PlayerConfig

Pass once at construction time. All fields are optional.

> **Design note:** `PlayerConfig` controls **how the player behaves and looks**
> (player-wide). Anything that describes **what** is being played — `title`,
> `startAt`, `isLive`, `posterUrl`, `storyboardUrl` — lives on
> [`PlayerSource`](#playersource) instead, so each video carries its own data.

```dart
CustomPlayerController(
  config: PlayerConfig(
    // ── Playback
    autoPlay: true,          // start immediately after open()
    loop: false,             // loop at completion
    initialSpeed: 1.0,       // 0.25 – 4.0
    initialVolume: 1.0,      // 0.0 – 1.0
    seekSeconds: 10,         // double-tap / skip-button amount

    // ── Buffering (ExoPlayer LoadControl, milliseconds)
    minBufferMs: 25000,                 // min media kept buffered
    maxBufferMs: 6553600,               // max media buffered
    bufferForPlaybackMs: 500,           // buffer before playback starts (fast start)
    bufferForPlaybackAfterRebufferMs: 6000, // buffer to resume after a rebuffer

    // ── Network
    loadingTimeoutSeconds: 30,          // 0 = no timeout
    autoRetryMaxAttempts: 3,            // auto-retry on error; 0 = off
    autoRetryBaseDelay: Duration(seconds: 2), // exponential backoff base

    // ── Screen
    useWakelock: true,              // keep screen on while playing
    aspectRatio: 16 / 9,            // null = stream's native ratio
    initialVideoFit: VideoFit.contain, // contain | cover | fill

    // ── UI
    accentColor: Color(0xFF0071EB),      // progress bar
    subtitlesConfiguration: BetterPlayerSubtitlesConfiguration(
      fontSize: 18,                      // subtitle appearance (see below)
      backgroundColor: Colors.black54,
    ),
    showControls: true,                  // false = video only, bring your own UI
    controlsTimeoutSeconds: 4,           // 0 = never auto-hide
    showBufferingIndicator: true,
    showTitle: true,                     // title in the top bar
    showLockButton: true,                // lock-screen button (top-right)
    showPipButton: true,                 // Picture-in-Picture button (mobile)
    showFullscreenButton: null,          // ⛶ expand: null = auto (off on TV)
    subtitleActions: [                   // extra entries in the subtitle sheet
      PlayerSheetAction(
        icon: Icons.search_rounded,
        label: 'Search online…',
        onTap: (context) => showMySubtitleSearch(context),
      ),
    ],

    // ── Callbacks
    onCompleted: () => _playNext(),
    onError: (msg) => print('Player error: $msg'),
    onPositionChanged: (pos) => _saveProgress(pos), // throttled ~1/sec
  ),
)
```

### Full reference

| Field | Default | Description |
|---|---|---|
| `autoPlay` | `true` | Begin playback immediately after `open()` |
| `loop` | `false` | Replay from the start on completion |
| `initialSpeed` | `1.0` | Playback rate, clamped to \[0.25, 4.0\] |
| `initialVolume` | `1.0` | Volume \[0.0, 1.0\] |
| `seekSeconds` | `10` | Double-tap / skip-button seek amount (5, 10, 30 use matching icons) |
| `minBufferMs` | `25000` | Min duration (ms) of media kept buffered (ExoPlayer LoadControl) |
| `maxBufferMs` | `6553600` | Max duration (ms) of media buffered |
| `bufferForPlaybackMs` | `500` | Media (ms) buffered before playback starts — main lever for fast startup |
| `bufferForPlaybackAfterRebufferMs` | `6000` | Media (ms) buffered to resume after a rebuffer |
| `loadingTimeoutSeconds` | `30` | Seconds before a stuck load shows a timeout error; `0` disables |
| `autoRetryMaxAttempts` | `3` | Automatic retries (exponential backoff) before showing the error overlay; `0` disables |
| `autoRetryBaseDelay` | `2s` | Base delay between retries (doubles each attempt, capped at 30s) |
| `useWakelock` | `true` | Prevents screen sleep during playback |
| `aspectRatio` | `null` | Forces canvas ratio; `null` = stream native |
| `initialVideoFit` | `VideoFit.contain` | Initial scaling: `contain` / `cover` / `fill` |
| `accentColor` | `Color(0xFFE50914)` | Colour of the played part of the progress bar. Focus and selection are drawn in translucent white, independent of it |
| `subtitlesConfiguration` | `BetterPlayerSubtitlesConfiguration()` | Subtitle appearance — see [Subtitle styling](#subtitle-styling) |
| `showControls` | `true` | Render the built-in controls overlay. `false` leaves only the video surface (plus poster/buffering/error) so the host can stack its own UI |
| `tvMode` | `TvMode.auto` | How the controls answer a remote/D-pad: `auto` (focus skin appears on the first key press), `enabled` (always — use it on Android TV), `disabled` (touch only) — see [Remote control / Android TV](#remote-control--android-tv) |
| `onSkipNext` | `null` | Called by the remote's ⏭ key; when null the key seeks forward instead |
| `onSkipPrevious` | `null` | Called by the remote's ⏮ key; when null the key seeks backwards |
| `controlsTimeoutSeconds` | `4` | Seconds of inactivity before auto-hide |
| `subtitleActions` | `[]` | Extra `PlayerSheetAction` entries appended to the subtitle sheet — see [Subtitles](#subtitles) |
| `showBufferingIndicator` | `true` | Show spinner while buffering |
| `showTitle` | `true` | Show the source title in the top bar |
| `showLockButton` | `true` | Show the lock-screen button (top-right) |
| `showPipButton` | `true` | Show the Picture-in-Picture button — Android/iOS only, and only when the device supports PiP — see [Picture-in-Picture](#picture-in-picture) |
| `showAspectRatioButton` | `null` | Show the aspect-ratio button (Fit → Zoom → Stretch); `null` = auto (shown on desktop/web/TV, hidden on mobile where pinch does the same), or force `true`/`false` |
| `showFullscreenButton` | `null` | Show the ⛶ fullscreen button (top-right); `null` = auto (hidden while the TV chrome is on, shown otherwise), or force `true`/`false`. `false` also drops the ⛶ exit button — nothing can open the fullscreen route without the first one |
| `showVolumeControl` | `null` | Inline volume control; `null` = auto (hidden on mobile, where the OS volume keys are used), or force `true`/`false` |
| `onCompleted` | `null` | Callback when playback finishes |
| `onError` | `null` | Callback with error message string |
| `telemetry` | `null` | Playback telemetry reporting — see [Telemetry](#telemetry) |
| `onPlaybackEvent` | `null` | Receives every measured playback event, to report it wherever you want — see [Reporting to your own backend](#reporting-to-your-own-backend) |
| `onPositionChanged` | `null` | Throttled (~1/sec) position callback — ideal for resume tracking |

---

## Telemetry

The player can report playback consumption to your API on its own: how much was
actually watched, how long startup took, how often it rebuffered and at which
quality.

```dart
final controller = CustomPlayerController(
  config: PlayerConfig(
    telemetry: TelemetryConfig(
      apiUrl: 'https://api.example.com/api/telemetry',
      authToken: sanctumToken,                 // Authorization: Bearer …
      appVersion: '3.4.1',
      deviceType: TelemetryDeviceType.android, // .tv on Android TV
    ),
  ),
);

await controller.open(PlayerSource.network(
  url,
  contentId: 812,    // ← without this the source is played but not reported
  episodeId: 4711,   // null for movies
));
```

### What gets sent

`POST {apiUrl}` with `Authorization: Bearer <token>` and
batches of 1–50 events, oldest first:

```jsonc
{
  "deviceType": "android",
  "kind": "playback",
  "appVersion": "3.4.1",
  "events": [
    {
      "type": "progress",                        // start | progress | end | error
      "sessionId": "01J4X8Y3NDQ2M9V7B1KQZT5W6E", // ULID, one per media load
      "occurredAt": "2026-08-06T22:30:30-03:00", // always with offset
      "contentId": 812,
      "episodeId": 4711,
      "positionSeconds": 1284,
      "secondsWatchedDelta": 30,                 // since the previous event
      "stallCountDelta": 1,
      "stalledSecondsDelta": 4,
      "resolution": "1080"
    }
  ]
}
```

Event cycle, handled for you:

| Event | When | Carries |
|---|---|---|
| `start` | first frame | `startupMs`, every delta at zero |
| `progress` | every 30s **while playing** — never paused or backgrounded | the deltas of the interval |
| `end` | playback stops, the source changes, the player is disposed, or the app is detached | the pending deltas |
| `error` | fatal player error (after auto-retries are exhausted) | the pending deltas, never the error text — that belongs in Sentry |

Every counter is a **delta since the previous event of the same session** and is
reset once queued, so a lost report costs one interval and nothing else.
`secondsWatchedDelta` follows the playhead while playing — pauses don't count and
seeks are discarded, not billed as watched time. A rebuffer counts once, when it
begins, so a freeze spanning several `progress` events stays one stall.

`sessionId` is a ULID generated per media load (repeats of the same title
included) and repeated on every event of that playback — it is what groups the
events of one session server-side and lets a re-sent queue be deduplicated.

Two deliberate contract details, both enforced at serialisation so a bad reading
can never 422 a whole batch: **no numeric field is ever sent as `null`** (an
absent key is 0 server-side, an explicit null is a validation error), and every
value is clamped to the accepted range. A `422` is always logged with its status
and batch size, `verbose` or not — the batch is dropped from the queue on 422, so
a silent one would read as "reporting fine, no data".

**A fatal error before the first frame is not reported.** That session never sent
a `start`, so the server has no open session to close, and its error rate is
computed over sessions it has seen. It is logged locally and your crash reporting
still sees it.

### Reporting to your own backend

Measuring the session and reporting it are two different jobs, and only the
first one needs to live in the player. `onPlaybackEvent` hands you every event
the player measures — the same ones the built-in reporter would send — so you
can file them wherever you want:

```dart
CustomPlayerController(
  config: PlayerConfig(
    onPlaybackEvent: (PlaybackEvent event) {
      myAnalytics.record(event);   // your API, your payload, your queue
    },
  ),
);
```

Setting it is enough to start measuring: `TelemetryConfig` is **not** required,
and without it nothing is queued or sent anywhere. With both set, one
measurement feeds both destinations — each event reaches your callback and the
built-in reporter **exactly once, and identical**, with the same `sessionId`,
the same deltas and the same `occurredAt`.

The same rule applies as to the built-in reporter: **a source without a
`contentId` produces no events at all**, so the callback is never invoked for
it. Everything the player measures hangs off that id.

The callback runs on the player's thread as the event is measured: keep it
quick and hand real work to your own queue. An exception thrown inside it is
caught and logged — it never breaks playback, and never disturbs the built-in
queue.

`PlaybackEvent` is a plain measurement record with no wire format of its own:
the API payload above (its field names, its caps, its timestamp format) is
produced by the telemetry layer, not by the event. `TelemetryEvent` and
`TelemetryEventType` remain valid as aliases of `PlaybackEvent` /
`PlaybackEventType`.

### Delivery

Events are appended to a persistent on-disk queue (`<app-support>/mk_player/
telemetry_queue.jsonl`) the moment they happen, so a killed process, an offline
TV or a lost connection cannot drop them. The queue is drained every 60s, and on
every session end. Events leave the queue **only** on `204` (accepted) or `422`
(never going to work — logged); `429` and network errors keep them and retry with
exponential backoff honouring `Retry-After`, and `401` holds the whole queue:

```dart
// After a re-login, hand the player the new token and the backlog goes out.
controller.updateTelemetryToken(freshToken);
```

Backlogs over 50 events are sent in several requests, and the queue is capped
(`maxQueuedEvents`, 500 by default) by dropping the oldest.

### `bytesDownloadedDelta`

The Flutter layer of ExoPlayer/Media3 does not expose `AnalyticsListener`
counters, so mk_player cannot see real network traffic. Rather than estimate it
from the bitrate — which would report traffic that never happened, and non-zero
bytes for a local file — the field is **omitted** from the payload unless you
wire a counter:

```dart
TelemetryConfig(
  // …
  // Cumulative bytes loaded by the player; the reporter turns it into deltas.
  bytesLoadedProvider: () => MyNativeBridge.totalBytesLoaded(),
)
```

The counter must be **bytes that really crossed the network** — a title played
from local storage has to report 0. On Android that means an ExoPlayer
`AnalyticsListener` in the plugin: either `onBandwidthEstimate(…,
totalBytesLoaded, …)`, or the sum of `LoadEventInfo.bytesLoaded` in
`onLoadCompleted` for finer granularity, exposed over a method channel. **This
bridge lives in the `better_player_plus` fork, not in this package, and is not
implemented yet** — until it is, the field is absent from every payload and the
bandwidth metric stays empty.

### `TelemetryConfig` reference

| Field | Default | Description |
|---|---|---|
| `apiUrl` | — | Full endpoint URL, e.g. `https://api.example.com/api/telemetry` |
| `authToken` | `null` | Token sent as `Authorization: Bearer …` on every request |
| `tokenProvider` | `null` | Resolves the token per request; wins over `authToken` |
| `appVersion` | — | Reported as `appVersion` (truncated to 32 chars) |
| `deviceType` | `.android` | `.web`, `.android`, `.tv` or `.other` |
| `kind` | `.playback` | `.playback` or `.download` |
| `progressInterval` | `30s` | Spacing of `progress` events while playing |
| `flushInterval` | `60s` | How often the queue is drained |
| `maxBatchSize` | `50` | Events per request (API maximum) |
| `maxQueuedEvents` | `500` | Queue cap; oldest are dropped past it |
| `retryBaseDelay` | `5s` | Backoff base, doubling up to 15 min |
| `queueFilePath` | `null` | Override the queue file location |
| `bytesLoadedProvider` | `null` | Cumulative network bytes counter |
| `enabled` | `true` | `false` keeps the wiring but reports nothing |
| `verbose` | `false` | `debugPrint` queue/flush activity |

### Verifying

With `verbose: true`, play 30 seconds and check the log:

1. a `start` (with `startupMs` > 0) and at least one `progress`, both answered
   with 204;
2. the reported seconds match what was actually played;
3. `bytesDownloadedDelta` is plausible for the chosen quality — a 0, or an absent
   key, means the native bridge above is not wired;
4. closing the player emits an `end` with the pending deltas.

Any `422` is a payload-contract mismatch and is printed with its status and batch
size.

---

## Subtitle styling

Subtitle appearance is configured with better_player's
`BetterPlayerSubtitlesConfiguration` (re-exported by `mk_player`), passed once
at construction time:

```dart
PlayerConfig(
  subtitlesConfiguration: BetterPlayerSubtitlesConfiguration(
    fontSize: 14,                        // logical pixels
    fontColor: Colors.white,
    fontFamily: 'Roboto',
    backgroundColor: Colors.transparent, // box behind the text
    outlineEnabled: true,                // stroke around glyphs
    outlineColor: Colors.black,
    outlineSize: 2.0,
    bottomPadding: 20,                   // distance from the bottom edge
    leftPadding: 8,
    rightPadding: 8,
    alignment: Alignment.center,
  ),
)
```

Common presets:

```dart
// YouTube-style: text on a semi-transparent black band
BetterPlayerSubtitlesConfiguration(backgroundColor: Colors.black54, outlineEnabled: false)

// Classic TV captions: yellow text with a black outline
BetterPlayerSubtitlesConfiguration(fontColor: Colors.yellow)
```

---

## CustomPlayerController

### State

```dart
controller.state         // MkPlayerState enum
controller.isPlaying     // bool convenience getters
controller.isPaused
controller.isBuffering
controller.isLoading
controller.isCompleted
controller.hasError

controller.position      // Duration — current playback position
controller.duration      // Duration — total stream duration
controller.buffered      // Duration — buffered ahead position
controller.remaining     // Duration — time left
controller.progress      // double 0.0–1.0

controller.volume        // double 0.0–1.0 (accounts for mute)
controller.rawVolume     // double without mute flag
controller.muted         // bool
controller.speed         // double
controller.errorMessage  // String? — last error from ExoPlayer
controller.currentTitle  // String? — title from PlayerSource
controller.storyboard    // Storyboard? — loaded VTT, null if none
```

### MkPlayerState values

```
idle → loading → buffering → playing → paused
                                     ↓
                                  completed
                           error (from any state)
```

### Playback control

```dart
await controller.play();
await controller.pause();
await controller.togglePlayPause();
await controller.seek(Duration(seconds: 90));
await controller.setVolume(0.8);   // 0.0 – 1.0
await controller.toggleMute();
await controller.setSpeed(1.5);    // 0.25 – 4.0
await controller.retry();          // re-open last source after an error
```

### Track management

Tracks are parsed from the HLS/DASH manifest after the source opens and use
`better_player_plus` types (re-exported from `mk_player`):

```dart
final audios    = controller.audioTracks;     // List<BetterPlayerAsmsAudioTrack>
final videos    = controller.videoTracks;     // List<BetterPlayerAsmsTrack>
final subtitles = controller.subtitleSources; // List<BetterPlayerSubtitlesSource>

// Currently-selected tracks (nullable)
controller.selectedAudioTrack; // BetterPlayerAsmsAudioTrack?
controller.selectedVideoTrack; // BetterPlayerAsmsTrack?
controller.selectedSubtitle;   // BetterPlayerSubtitlesSource?

// Whether any real (non-"off") subtitle exists
controller.hasSubtitles; // bool

// Switch audio language
controller.setAudioTrack(audios[1]);

// Enable subtitles
await controller.setSubtitle(subtitles.first);

// Turn off subtitles
await controller.disableSubtitles();

// Add a track that only exists mid-playback (just downloaded, picked from
// storage…) — inserted before "Off" and selected unless select: false
final added = await controller.addExternalSubtitle(
  ExternalSubtitle(uri: '/data/user/0/app/files/subs/es.srt', title: 'Español'),
);

// And remove it again (falls back to "Off" if it was the selected one)
await controller.removeSubtitle(added);

// Force a video quality / bitrate
controller.setVideoTrack(videos[2]);
```

### Listening to changes

`CustomPlayerController` extends `ChangeNotifier`. Use `ListenableBuilder`
for reactive widgets:

```dart
ListenableBuilder(
  listenable: _controller,
  builder: (context, _) {
    return Text(
      '${_controller.position.inSeconds}s / '
      '${_controller.duration.inSeconds}s',
    );
  },
)
```

Or use `addListener` / `removeListener` for imperative code:

```dart
void _onStateChange() {
  if (_controller.isCompleted) _showEndCard();
}

@override
void initState() {
  super.initState();
  _controller.addListener(_onStateChange);
}

@override
void dispose() {
  _controller.removeListener(_onStateChange);
  _controller.dispose();
  super.dispose();
}
```

---

## PlayerView

Drop-in widget. Renders the video surface and all UI overlays.

```dart
// Fill a screen
PlayerView(controller: _controller)

// With custom config
PlayerView(
  controller: _controller,
  config: PlayerConfig(
    accentColor: Colors.blue,
    aspectRatio: 16 / 9,
  ),
)

// Embedded in a card (respects its parent's constraints)
SizedBox(
  height: 220,
  child: PlayerView(controller: _controller),
)
```

### Built-in UI

A premium, streaming-app-style control layer (inspired by Netflix / Apple TV+):

- **Top bar** — back/exit, title, 🔒 lock-screen, ⛶ fullscreen
- **Centre** — rewind · play/pause · forward
- **Bottom** — scrubber with thumbnail preview, elapsed/remaining time, volume,
  and a labeled action row: **Speed**, **Audio**, **Subtitles**
  (Audio/Subtitles appear only when the stream actually has those tracks)

Under a remote the layout is trimmed to what a D-pad can reach — see
[Remote control / Android TV](#remote-control--android-tv).

| Gesture / control | Action |
|---|---|
| Single tap | Show / hide controls |
| Double-tap left `< 40%` | Rewind `seekSeconds` (default 10s) |
| Double-tap right `> 60%` | Forward `seekSeconds` |
| Drag progress bar | Seek with thumbnail preview |
| Tap time label | Toggle total ↔ remaining time |
| Pinch in / out | Switch aspect ratio (fit ↔ zoom) |
| **Speed / Audio / Subtitles** | Open a focused bottom sheet for that setting |
| 🔒 Lock | Lock the screen — disables all gestures until you tap to unlock |
| Volume icon | Mute toggle + inline slider with live `%` (when enabled via `showVolumeControl`) |
| ⛶ Fullscreen | Landscape orientation lock + immersive system UI |

For sources opened with `isLive: true`, a red **LIVE** badge replaces the
duration and the scrubber is disabled. Liveness is never auto-detected — set
the flag explicitly on the `PlayerSource`.

### Remote control / Android TV

The same overlay is driven by a D-pad. Every control is focusable, the focused
one wears a white ring, and the seek bar is a focus target of its own so the
arrows scrub instead of jumping between buttons.

```dart
CustomPlayerController(
  config: const PlayerConfig(
    tvMode: TvMode.enabled,   // Android TV / leanback app
  ),
)
```

| Key | Controls hidden | Controls visible |
|---|---|---|
| **← / →** | reveal the bar and start scrubbing | scrub (seek bar focused) · move focus (button focused) |
| **↑ / ↓** | reveal the bar | move focus between rows |
| **OK / centre** | reveal the bar | play/pause (seek bar focused) · press the button |
| **Back** | closes the player | hides the controls |
| **▶⏸ / ▶ / ⏸ / ⏹** | act immediately | act immediately |
| **⏪ / ⏩** | scrub | scrub |
| **⏮ / ⏭** | `onSkipPrevious` / `onSkipNext`, else scrub | idem |

Holding **←/→** accelerates — the step grows from 1× to 6× `seekSeconds` — and
the seek is committed ~400 ms after the last press, so a long scrub is a single
seek with a live preview on the bar (thumbnail included, when a storyboard is
attached) instead of thirty separate ones.

`tvMode` decides when the focus skin appears:

| Value | Behaviour |
|---|---|
| `TvMode.auto` *(default)* | Keys are always handled; the focus ring, the focusable seek bar and the back-hides-controls rule switch on the first time a key is pressed. A phone build is untouched until someone plugs in a remote or a keyboard. |
| `TvMode.enabled` | On from the first frame. **Use this in an Android TV app** — the controls are navigable before any key is pressed. |
| `TvMode.disabled` | No key handling at all, touch only. |

#### What the TV chrome leaves out

The remote already does these, so the buttons only cost focus stops:

| Dropped on TV | Why · what replaces it |
|---|---|
| ◀ back arrow (top-left) | The remote's **Back** key: it closes the controls first, then the player |
| ⏪ / ⏩ ±`seekSeconds` buttons | **← / →** scrub, with acceleration. The centre play/pause stays as a state indicator (out of the focus order) |
| **Speed** | A lean-forward control; `CustomPlayerController.setSpeed` is still there for a host-supplied one |
| 🔒 **Lock** | A locked screen is a trap without a touchscreen |
| ⛶ **Fullscreen** | The video already fills the screen, and a TV has no window or orientation to manage. Force it back with `showFullscreenButton: true` |

The **Audio** and **Subtitles** buttons also collapse into a single
**Audio & Subtitles** entry — see below.

#### The track panel

On touch, each list is a bottom sheet of its own. That costs a remote four extra
presses and covers the very subtitles the user is trying to pick, so on TV both
lists live in one panel pinned to the right edge:

- one column per type (**Audio**, **Subtitles**), side by side, each only as
  tall as its own entries and scrolling only if there are more tracks than fit;
- **↑ / ↓** moves inside a column, **← / →** between columns;
- focus opens on the track that is playing, in the leftmost column;
- **OK** applies the track immediately and *keeps the panel open*, so a wrong
  guess is one press away from being fixed — the check mark moves as you go;
- **Back** (or a click on the dimmed video) closes it.

`subtitleActions` entries appear under the subtitle column, below a divider, and
still close the panel before running — they typically push a route of their own.

For the manifest flags an Android TV app needs, see
[Android TV setup](#android-tv-setup).

### Bringing your own controls

The built-in overlay handles touch, mouse and remotes. Where it still does not
fit — a kiosk layout, an embedded preview, a bespoke TV design — set
`showControls: false` and stack your own UI on top. `PlayerView` still renders
the video surface, poster, buffering spinner and error overlay; everything else
is yours, driven by the same `CustomPlayerController`:

```dart
Stack(
  children: [
    PlayerView(
      controller: _controller,
      config: _controller.config.copyWith(showControls: false),
    ),
    MyTvControls(controller: _controller), // your focusable widgets
  ],
)
```

---

## Storyboard thumbnail scrubber

While the user drags the progress bar, a thumbnail popup appears above the
thumb showing the video frame at that position. Attach a WebVTT storyboard URL
to the `PlayerSource` — the player fetches and parses it in the background
without blocking playback.

```dart
controller.open(
  PlayerSource.network(
    'https://cdn.example.com/video.m3u8',
    storyboardUrl: 'https://cdn.example.com/storyboard.vtt',
    // optional — only if the endpoint requires auth:
    storyboardHeaders: {'Authorization': 'Bearer $token'},
  ),
);
```

### Expected VTT format

```
WEBVTT

00:00:00.000 --> 00:00:05.000
https://cdn.example.com/sprites.jpg#xywh=0,0,160,90

00:00:05.000 --> 00:00:10.000
https://cdn.example.com/sprites.jpg#xywh=160,0,160,90

00:00:10.000 --> 00:00:15.000
https://cdn.example.com/sprites.jpg#xywh=320,0,160,90
```

`#xywh=x,y,width,height` identifies the crop region inside the sprite sheet.
Relative image URLs are resolved against the VTT base URL.
Individual frame files (one URL per cue, no fragment) are also supported.

---

## Subtitles

The subtitle selector lists, in order:

1. **Off** — disables subtitles
2. **Embedded tracks** — subtitles muxed into the media (read from the stream)
3. **External tracks** — extra files you supply via `externalSubtitles`

External subtitles are loaded as URIs (SRT, WebVTT, ASS, …) and appear next to
the embedded ones — both coexist in the same menu:

```dart
controller.open(
  PlayerSource.network(
    'https://cdn.example.com/movie.mp4',
    externalSubtitles: const [
      ExternalSubtitle(
        uri: 'https://cdn.example.com/subs/en.vtt',
        title: 'English',
        language: 'en',
      ),
      ExternalSubtitle(
        uri: '/storage/emulated/0/subs/es.srt', // local file also works
        title: 'Español',
        language: 'es',
        selectedByDefault: true,  // start with this one already on
      ),
    ],
  ),
);
```

Any `uri` that does not start with `http://` or `https://` is read from disk;
network ones are downloaded. Subtitles never inherit the video's `headers` —
they usually live on a different host — so pass them per track when the
endpoint needs auth:

```dart
ExternalSubtitle(
  uri: 'https://cdn.example.com/subs/en.vtt',
  title: 'English',
  headers: {'Authorization': 'Bearer $token'},
)
```

Nothing is displayed until a track is selected: set `selectedByDefault: true`
on one of them (or call `setSubtitle`) if subtitles should be on from the
start.

You can also build the list from a `label → uri` map:

```dart
externalSubtitles: ExternalSubtitle.fromMap(
  {
    'English': 'https://cdn.example.com/en.vtt',
    'Español': 'https://cdn.example.com/es.vtt',
  },
  selectFirst: true, // enable the first entry on open
),
```

> The subtitle list includes an "off" entry; `controller.hasSubtitles` reports
> whether there is at least one real, selectable subtitle to choose from.

### Host actions in the subtitle sheet

`PlayerConfig.subtitleActions` appends your own entries below the track list —
the hook for app-specific flows such as downloading from an online provider.
They are shown even when the media has no subtitle tracks, and the sheet closes
before the callback runs, so it is safe to push a route or open another sheet:

```dart
PlayerConfig(
  subtitleActions: [
    PlayerSheetAction(
      icon: Icons.search_rounded,
      label: 'Search subtitles online…',
      onTap: (context) async {
        final file = await showMySubtitleBrowser(context); // your UI
        if (file != null) {
          await controller.addExternalSubtitle(
            ExternalSubtitle(uri: file.path, title: file.language),
          );
        }
      },
    ),
  ],
)
```

---

## Fullscreen

Fullscreen is handled automatically by `PlayerView`. Tapping the ⛶ icon locks
orientation to landscape, hides system UI (immersive mode), and pushes a
covering route over the root navigator.

Exiting (via the exit button or the system back gesture) restores the previous
orientation and system UI.

---

## Picture-in-Picture

A PiP button is rendered in the top controls bar on Android and iOS, as soon as
the native side confirms the device supports it. No wiring is needed beyond the
platform setup below; hide it with `showPipButton: false`.

```dart
PlayerConfig(showPipButton: true) // default
```

### Android setup

PiP is a property of the **host activity**, so it must be declared in your app's
`android/app/src/main/AndroidManifest.xml`:

```xml
<activity
    android:name=".MainActivity"
    android:supportsPictureInPicture="true"
    android:resizeableActivity="true"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    ... >
```

Without `supportsPictureInPicture` the button still appears (the device *does*
support PiP) but entering fails with a log line explaining exactly this.

Android puts the **whole activity** into the PiP window, so `PlayerView` enters
its own fullscreen first — otherwise the rest of your page would be miniaturised
along with the video. When the PiP window closes the player stays fullscreen;
the user leaves it with the exit-fullscreen button or the back gesture.

### iOS setup

Enable the **Audio, AirPlay, and Picture in Picture** background mode in Xcode
(`Signing & Capabilities → Background Modes`), which adds to `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

### Driving PiP yourself

```dart
await _controller.enterPip();   // opens the PiP window
await _controller.exitPip();    // closes it (Android sends the task to the back)
_controller.pipSupported        // native answer, false until the first frame
_controller.pipActive           // true while the PiP window is open
```

If you drive PiP with your own mechanism (e.g. the `floating` package) instead
of the built-in button, tell the player about it so the controls overlay reacts:

```dart
_controller.notifyPipEntered(); // hides controls overlay
_controller.notifyPipExited();  // restores controls overlay
```

OS-initiated PiP changes (closing the window, the system "back to app" button)
are picked up automatically — the player mirrors the native `pipStart`/`pipStop`
events.

---

## Error handling

When the player encounters an unrecoverable error (expired token, network loss,
unsupported codec, 30 s timeout), it transitions to `MkPlayerState.error` and
shows a full-screen overlay with a **Try Again** button and a back button.

```dart
// React in the host app
PlayerConfig(
  onError: (message) {
    analytics.track('player_error', {'message': message});
    if (message.contains('403')) _refreshToken();
  },
)

// Or observe state directly
ListenableBuilder(
  listenable: _controller,
  builder: (_, __) {
    if (_controller.hasError) {
      return Text('Error: ${_controller.errorMessage}');
    }
    return const SizedBox.shrink();
  },
)
```

---

## Complete example

```dart
import 'package:flutter/material.dart';
import 'package:mk_player/mk_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const VideoScreen(),
    );
  }
}

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final CustomPlayerController _controller;

  @override
  void initState() {
    super.initState();

    _controller = CustomPlayerController(
      config: PlayerConfig(
        autoPlay: true,
        accentColor: const Color(0xFF0071EB),
        onCompleted: () => debugPrint('Playback finished'),
        onError: (msg) => debugPrint('Error: $msg'),
      ),
    );

    _controller.open(
      PlayerSource.network(
        'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        title: 'Big Buck Bunny',
        headers: {'User-Agent': 'MyApp/1.0'},
        storyboardUrl: 'https://cdn.example.com/storyboard.vtt',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PlayerView(controller: _controller),
    );
  }
}
```

---

## Package structure

```
lib/
├── mk_player.dart                  ← single import for host apps
└── src/
    ├── controller.dart             ← CustomPlayerController (ChangeNotifier)
    ├── player_view.dart            ← PlayerView + fullscreen route
    ├── models/
    │   ├── player_config.dart      ← PlayerConfig
    │   ├── player_source.dart      ← PlayerSource
    │   └── storyboard.dart         ← Storyboard + VTT parser
    ├── playback/                    ← measurement, no IO
    │   ├── playback_event.dart      ← PlaybackEvent (aka TelemetryEvent)
    │   └── playback_session_tracker.dart ← measures the session, feeds sinks
    ├── telemetry/                   ← transport to the built-in API
    │   ├── telemetry_config.dart    ← TelemetryConfig
    │   ├── telemetry_serializer.dart ← payload format, clamps, session id rules
    │   ├── telemetry_queue.dart     ← persistent on-disk queue
    │   ├── telemetry_client.dart    ← POST /api/telemetry
    │   └── telemetry_reporter.dart  ← queue + delivery (a sink of the tracker)
    └── widgets/
        ├── controls_overlay.dart   ← auto-hiding controls
        ├── progress_bar.dart       ← scrubber + thumbnail popup
        ├── thumbnail_preview.dart  ← sprite sheet cropping widget
        ├── settings_sheet.dart     ← audio / subtitle / speed sheet
        └── error_overlay.dart      ← error state UI
```

---

## Dependencies

| Package | Purpose |
|---|---|
| `better_player_plus` (1.2.1) | Core player engine (ExoPlayer on Android) |
| `wakelock_plus` | Screen sleep prevention |
| `path_provider` | Location of the persistent telemetry queue |
| `xml` | DASH manifest parsing |

---

## License

MIT
