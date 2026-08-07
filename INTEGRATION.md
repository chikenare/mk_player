# mk_player — Integration Guide

A concise walkthrough for adding `mk_player` to any Flutter application.

---

## 1. Link the package locally

In your **host app's** `pubspec.yaml`, add a path dependency:

```yaml
dependencies:
  flutter:
    sdk: flutter
  mk_player:
    path: ../mk_player        # adjust relative path as needed
```

Run:

```bash
flutter pub get
```

---

## 2. Platform setup

> `mk_player` supports **Android only**.

### Android

`android/app/build.gradle` — set the minimum SDK to **21**:

```groovy
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

For network streams over HTTP (non-HTTPS), allow cleartext traffic in
`android/app/src/main/AndroidManifest.xml`:

```xml
<application
    android:usesCleartextTraffic="true"
    ...>
```

---

## 3. Initialise `main.dart`

No special player initialisation is required — just the standard Flutter binding
call **before** `runApp`:

```dart
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}
```

---

## 4. Basic usage

```dart
import 'package:mk_player/mk_player.dart';

class VideoScreen extends StatefulWidget {
  final String streamUrl;
  final String? authToken;

  const VideoScreen({super.key, required this.streamUrl, this.authToken});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final CustomPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CustomPlayerController(
      config: const PlayerConfig(
        autoPlay: true,
        useWakelock: true,
        accentColor: Color(0xFF0071EB),
      ),
    );

    _openSource();
  }

  Future<void> _openSource() async {
    await _controller.open(
      PlayerSource.network(
        widget.streamUrl,
        headers: {
          if (widget.authToken != null)
            'Authorization': 'Bearer ${widget.authToken}',
          'User-Agent': 'MyApp/1.0',
        },
        title: 'My Video',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();   // ← always dispose to prevent memory leaks
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

## 5. Opening a local file

```dart
import 'dart:io';

await _controller.open(
  PlayerSource.file('/storage/emulated/0/Movies/sample.mp4'),
);
```

---

## 6. Playlist

```dart
await _controller.openPlaylist([
  PlayerSource.network('https://cdn.example.com/ep1.m3u8'),
  PlayerSource.network('https://cdn.example.com/ep2.m3u8'),
]);
```

---

## 7. Track management

Tracks use `better_player_plus` types, re-exported from `mk_player`
(`BetterPlayerAsmsAudioTrack`, `BetterPlayerAsmsTrack`,
`BetterPlayerSubtitlesSource`).

```dart
// After the source is open, read available tracks:
final audioTracks      = _controller.audioTracks;     // List<BetterPlayerAsmsAudioTrack>
final videoTracks      = _controller.videoTracks;     // List<BetterPlayerAsmsTrack>
final subtitleSources  = _controller.subtitleSources; // List<BetterPlayerSubtitlesSource>

// Switch audio language:
_controller.setAudioTrack(audioTracks[1]);

// Force a video quality:
_controller.setVideoTrack(videoTracks[2]);

// Enable subtitles:
await _controller.setSubtitle(subtitleSources.first);

// Disable subtitles:
await _controller.disableSubtitles();
```

---

## 8. Listening to state changes

`CustomPlayerController` extends `ChangeNotifier`. Wrap your widget with
`ListenableBuilder` (or `AnimatedBuilder`) for reactive updates:

```dart
ListenableBuilder(
  listenable: _controller,
  builder: (context, _) {
    return Text(
      'Position: ${_controller.position.inSeconds}s / '
      '${_controller.duration.inSeconds}s',
    );
  },
)
```

---

## 9. Picture-in-Picture

The controls overlay ships a **PiP button** (top bar, next to fullscreen). It
appears on Android and iOS once the native player confirms the device supports
PiP, and is hidden everywhere else. Turn it off with:

```dart
PlayerConfig(showPipButton: false)
```

### Android — required manifest flags

PiP belongs to the host activity, so add to your app's `AndroidManifest.xml`:

```xml
<activity
    android:name=".MainActivity"
    android:supportsPictureInPicture="true"
    android:resizeableActivity="true"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    ... >
```

Android miniaturises the whole activity, so `PlayerView` switches to fullscreen
before opening PiP; after the PiP window closes the player remains fullscreen.

### iOS

Enable the *Audio, AirPlay, and Picture in Picture* background mode
(`Signing & Capabilities → Background Modes`) in your Runner target.

### Programmatic control

```dart
await _controller.enterPip();  // open
await _controller.exitPip();   // close
_controller.pipSupported;      // resolved natively after the first frame
_controller.pipActive;         // true while the PiP window is open
```

### Custom PiP mechanisms

Using something else (e.g. the `floating` package)? Keep the UI in sync:

```dart
_controller.notifyPipEntered();   // hides controls overlay
_controller.notifyPipExited();    // restores controls overlay
```

OS-driven changes are mirrored automatically from the native
`pipStart`/`pipStop` events.

---

## 10. Embedding vs full-screen

`PlayerView` starts in **embedded** mode, respecting its parent's constraints.
The built-in fullscreen button triggers `SystemChrome` orientation locking and
pushes a covering route automatically. No extra configuration is required.

To control the aspect ratio manually:

```dart
PlayerView(
  controller: _controller,
  config: const PlayerConfig(aspectRatio: 16 / 9),
)
```

---

## 11. Playback telemetry

Configure it once on the controller and give every source its `contentId`; the
player does the rest (`start` / `progress` / `end` / `error`, on-disk queue,
retries).

```dart
_controller = CustomPlayerController(
  config: PlayerConfig(
    telemetry: TelemetryConfig(
      apiBaseUrl: 'https://api.example.com',
      authToken: sanctumToken,
      appVersion: packageInfo.version,
      // Android TV reports as a different device class:
      deviceType: isAndroidTv ? TelemetryDeviceType.tv : TelemetryDeviceType.android,
    ),
  ),
);

await _controller.open(PlayerSource.network(
  streamUrl,
  title: 'Episode 3',
  contentId: 812,     // required, or the playback is not reported
  episodeId: 4711,    // null for movies
));
```

After a re-login, release the events a `401` held back:

```dart
_controller.updateTelemetryToken(newToken);
```

Requires the `INTERNET` permission (already needed for streaming) and nothing
else — the queue lives in the app support directory via `path_provider`.

See the [Telemetry section of the README](README.md#telemetry) for the payload
contract, the delivery rules and why `bytesDownloadedDelta` needs a native
counter to be reported.

---

## 12. Configuration reference

| `PlayerConfig` field            | Default          | Description                                        |
|---------------------------------|------------------|----------------------------------------------------|
| `autoPlay`                      | `true`           | Start playback immediately after `open()`         |
| `loop`                          | `false`          | Loop at completion                                 |
| `initialSpeed`                  | `1.0`            | Playback speed (0.25–4.0)                         |
| `initialVolume`                 | `1.0`            | Volume (0.0–1.0)                                   |
| `minBufferMs`                   | `25000`          | Min media (ms) kept buffered (ExoPlayer LoadControl) |
| `maxBufferMs`                   | `6553600`        | Max media (ms) buffered                            |
| `bufferForPlaybackMs`           | `500`            | Media (ms) buffered before playback starts (fast start) |
| `bufferForPlaybackAfterRebufferMs` | `6000`        | Media (ms) buffered to resume after a rebuffer    |
| `useWakelock`                   | `true`           | Keep screen on during playback                    |
| `controlsTimeoutSeconds`        | `4`              | Seconds before controls auto-hide                 |
| `showBufferingIndicator`        | `true`           | Show spinner while buffering                      |
| `accentColor`                   | `Color(0xFFE50914)` | Progress bar + UI accent                       |
| `subtitlesConfiguration`        | `BetterPlayerSubtitlesConfiguration()` | Subtitle appearance: font size/colour/family, outline, background, paddings, alignment |
| `aspectRatio`                   | `null`           | Force canvas ratio (null = stream's native ratio) |
| `telemetry`                     | `null`           | `TelemetryConfig` for playback reporting (see §11) |
