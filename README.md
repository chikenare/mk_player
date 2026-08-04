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
| **Thumbnails** | WebVTT storyboard scrubber preview with sprite sheet support |
| **Fullscreen** | Landscape orientation lock + immersive SystemChrome |
| **Wakelock** | Screen stays on during playback, released on pause/error/dispose |
| **Error UI** | User-friendly overlay with Retry button and automatic 30 s timeout |
| **PiP** | Built-in Picture-in-Picture button (Android & iOS) plus lifecycle hooks |
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
    accentColor: Color(0xFF0071EB),      // progress bar + highlights
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
| `accentColor` | `Color(0xFFE50914)` | Accent colour for UI elements |
| `subtitlesConfiguration` | `BetterPlayerSubtitlesConfiguration()` | Subtitle appearance — see [Subtitle styling](#subtitle-styling) |
| `showControls` | `true` | Render the built-in controls overlay. `false` leaves only the video surface (plus poster/buffering/error) so the host can stack its own UI — e.g. a D-pad-navigable layout on Android TV |
| `controlsTimeoutSeconds` | `4` | Seconds of inactivity before auto-hide |
| `subtitleActions` | `[]` | Extra `PlayerSheetAction` entries appended to the subtitle sheet — see [Subtitles](#subtitles) |
| `showBufferingIndicator` | `true` | Show spinner while buffering |
| `showTitle` | `true` | Show the source title in the top bar |
| `showLockButton` | `true` | Show the lock-screen button (top-right) |
| `showPipButton` | `true` | Show the Picture-in-Picture button — Android/iOS only, and only when the device supports PiP — see [Picture-in-Picture](#picture-in-picture) |
| `showVolumeControl` | `null` | Inline volume control; `null` = auto (hidden on mobile, where the OS volume keys are used), or force `true`/`false` |
| `onCompleted` | `null` | Callback when playback finishes |
| `onError` | `null` | Callback with error message string |
| `onPositionChanged` | `null` | Throttled (~1/sec) position callback — ideal for resume tracking |

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

### Bringing your own controls

The built-in overlay is touch-first. Where that does not fit — Android TV with
a D-pad, a kiosk layout, an embedded preview — set `showControls: false` and
stack your own UI on top. `PlayerView` still renders the video surface, poster,
buffering spinner and error overlay; everything else is yours, driven by the
same `CustomPlayerController`:

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

---

## License

MIT
