# mk_player

A self-contained, highly reusable Flutter video player built on the [media_kit](https://pub.dev/packages/media_kit) ecosystem. Drop it into any app and get a premium streaming experience with zero boilerplate.

---

## Features

| | |
|---|---|
| **Formats** | HLS `.m3u8`, DASH `.mpd`, progressive HTTP/HTTPS, local files |
| **Auth** | Custom HTTP headers per source (`Authorization`, `Cookie`, `User-Agent`, …) |
| **Tracks** | Dynamic audio, subtitle and video-quality switching |
| **Controls** | Play/pause, seek, volume, mute, speed (0.25×–4×), double-tap ±10 s |
| **Thumbnails** | WebVTT storyboard scrubber preview with sprite sheet support |
| **Fullscreen** | Native macOS/Windows/Linux window expansion + mobile SystemChrome |
| **Wakelock** | Screen stays on during playback, released on pause/error/dispose |
| **Error UI** | User-friendly overlay with Retry button and automatic 30 s timeout |
| **PiP hooks** | Architecture hooks for iOS & Android Picture-in-Picture |
| **State** | `ChangeNotifier` — no third-party state library required |

---

## Requirements

| Platform | Minimum version |
|---|---|
| Android | SDK 21 |
| iOS | 12.0 |
| macOS | 10.15 |
| Windows | Windows 10 |
| Flutter | 3.16 |
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

#### iOS — `ios/Podfile`
```ruby
platform :ios, '12.0'
```

#### macOS — `macos/Podfile`
```ruby
platform :osx, '10.15'
```

No additional `Info.plist` or `AppDelegate` changes are required.
For HTTP (non-HTTPS) streams on iOS/macOS, add an App Transport Security exception.

---

## Initialisation

Call both initialisers **before** `runApp`. On desktop, `window_manager` must be
initialised so fullscreen works.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Required by media_kit on all platforms.
  MediaKit.ensureInitialized();

  // Required by window_manager on desktop for native fullscreen.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    await windowManager.ensureInitialized();
  }

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

  // HTTP headers forwarded to the native libmpv layer.
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

    // ── Network
    bufferSize: 32 * 1024 * 1024,       // 32 MB (bytes fed to libmpv)
    loadingTimeoutSeconds: 30,          // 0 = no timeout
    autoRetryMaxAttempts: 3,            // auto-retry on error; 0 = off
    autoRetryBaseDelay: Duration(seconds: 2), // exponential backoff base
    enableHardwareAcceleration: true,   // GPU decoding

    // ── Screen
    useWakelock: true,              // keep screen on while playing
    aspectRatio: 16 / 9,            // null = stream's native ratio
    initialVideoFit: VideoFit.contain, // contain | cover | fill

    // ── UI
    accentColor: Color(0xFF0071EB),      // progress bar + highlights
    controlsTimeoutSeconds: 4,           // 0 = never auto-hide
    showBufferingIndicator: true,
    showTitle: true,                     // title in the top bar
    showLockButton: true,                // lock-screen button (top-right)

    // ── Subtitles styling (pass a custom config)
    subtitleViewConfiguration: SubtitleViewConfiguration(
      style: TextStyle(fontSize: 32, color: Colors.white),
      padding: EdgeInsets.all(24),
    ),

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
| `bufferSize` | 32 MB | Native buffer size in bytes |
| `loadingTimeoutSeconds` | `30` | Seconds before a stuck load shows a timeout error; `0` disables |
| `autoRetryMaxAttempts` | `3` | Automatic retries (exponential backoff) before showing the error overlay; `0` disables |
| `autoRetryBaseDelay` | `2s` | Base delay between retries (doubles each attempt, capped at 30s) |
| `enableHardwareAcceleration` | `true` | GPU-accelerated decoding |
| `useWakelock` | `true` | Prevents screen sleep during playback |
| `aspectRatio` | `null` | Forces canvas ratio; `null` = stream native |
| `initialVideoFit` | `VideoFit.contain` | Initial scaling: `contain` / `cover` / `fill` |
| `subtitleViewConfiguration` | `null` | Custom subtitle styling (font, colour, background, padding) |
| `accentColor` | `Color(0xFFE50914)` | Accent colour for UI elements |
| `controlsTimeoutSeconds` | `4` | Seconds of inactivity before auto-hide |
| `showBufferingIndicator` | `true` | Show spinner while buffering |
| `showTitle` | `true` | Show the source title in the top bar |
| `showLockButton` | `true` | Show the lock-screen button (top-right) |
| `showVolumeControl` | `null` | Inline volume control; `null` = auto (desktop/web only), or force `true`/`false` |
| `onCompleted` | `null` | Callback when playback finishes |
| `onError` | `null` | Callback with error message string |
| `onPositionChanged` | `null` | Throttled (~1/sec) position callback — ideal for resume tracking |

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
controller.errorMessage  // String? — last error from libmpv
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

Available tracks populate after the source opens:

```dart
final audios    = controller.audioTracks;    // List<AudioTrack>
final subtitles = controller.subtitleTracks; // List<SubtitleTrack>
final videos    = controller.videoTracks;    // List<VideoTrack>

// Switch language
await controller.setAudioTrack(audios[1]);

// Enable subtitles
await controller.setSubtitleTrack(subtitles.first);

// Turn off subtitles
await controller.disableSubtitles();

// Force a video quality / bitrate
await controller.setVideoTrack(videos[2]);
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
| Pinch in / out (mobile) | Switch aspect ratio (fit ↔ zoom) |
| ⤢ Aspect-ratio button (desktop/web) | Cycle contain → cover → fill |
| **Speed / Audio / Subtitles** | Open a focused bottom sheet for that setting |
| 🔒 Lock | Lock the screen — disables all gestures until you tap to unlock |
| Volume icon | Mute toggle + inline slider with live `%` (desktop/web by default) |
| ⛶ Fullscreen | Native window expand (desktop) or landscape lock (mobile) |

For sources opened with `isLive: true`, a red **LIVE** badge replaces the
duration and the scrubber is disabled. Liveness is never auto-detected — set
the flag explicitly on the `PlayerSource`.

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
      ),
    ],
  ),
);
```

You can also build the list from a `label → uri` map:

```dart
externalSubtitles: ExternalSubtitle.fromMap({
  'English': 'https://cdn.example.com/en.vtt',
  'Español': 'https://cdn.example.com/es.vtt',
}),
```

> The sentinel `auto` / `no` tracks that the engine reports internally are
> filtered out — `controller.audioTracks` and `controller.subtitleTracks`
> return only real, selectable tracks.

---

## Fullscreen

Fullscreen is handled automatically by `PlayerView`. Tapping the ⛶ icon:

- **macOS / Windows / Linux** — calls `windowManager.setFullScreen(true)`,
  expanding the OS window to cover the entire display.
- **iOS / Android** — locks orientation to landscape, hides system UI, and
  pushes a covering route over the root navigator.

Exiting (via the exit button or the system back gesture) restores the previous
state on all platforms.

> **Requirement (desktop):** call `windowManager.ensureInitialized()` in
> `main()` before `runApp` — see [Initialisation](#initialisation).

---

## Picture-in-Picture

The package exposes lifecycle hooks. Wire your platform-specific PiP
implementation and call these two methods:

```dart
// When the OS enters PiP (e.g. user presses the PiP button)
_controller.notifyPipEntered(); // hides controls overlay

// When the PiP window is closed
_controller.notifyPipExited();  // restores controls overlay
```

### Android — `floating` package example

```dart
import 'package:floating/floating.dart';

final _floating = Floating();

Future<void> _enterPip() async {
  await _floating.enable(ImmediatePiP());
  _controller.notifyPipEntered();
}
```

Listen for the app lifecycle to detect when PiP closes:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    _controller.notifyPipExited();
  }
}
```

### iOS

Wire `AVPictureInPictureController` through a method channel or platform view.
Call `notifyPipEntered()` / `notifyPipExited()` from the channel callback.

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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mk_player/mk_player.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    await windowManager.ensureInitialized();
  }

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
| `media_kit` | Core player engine (libmpv) |
| `media_kit_video` | Video surface rendering |
| `media_kit_libs_video` | Native FFmpeg/libmpv binaries |
| `wakelock_plus` | Screen sleep prevention |
| `window_manager` | Native window fullscreen on desktop |

---

## License

MIT
