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

### Android

`android/app/build.gradle` — set the minimum SDK to **21**:

```groovy
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

### iOS

`ios/Podfile` — set the platform to **12.0** or higher:

```ruby
platform :ios, '12.0'
```

No further `Info.plist` entries are needed for basic playback. For network streams over HTTP (non-HTTPS), add an App Transport Security exception.

### Desktop (macOS / Windows / Linux)

No extra steps are required — `media_kit_libs_video` ships the native FFmpeg
libraries for all desktop targets.

---

## 3. Initialise media_kit in `main.dart`

`media_kit` requires a one-time native initialisation call **before** `runApp`:

```dart
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();   // ← required
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

```dart
// After the source is open, read available tracks:
final audioTracks    = _controller.audioTracks;
final subtitleTracks = _controller.subtitleTracks;

// Switch audio language:
await _controller.setAudioTrack(audioTracks[1]);

// Enable subtitles:
await _controller.setSubtitleTrack(subtitleTracks.first);

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

`mk_player` exposes **lifecycle hooks** so the host application can integrate
its chosen PiP mechanism and the player UI reacts correctly.

### Android (`floating` package example)

```dart
// Enter PiP (call from your Activity or using the `floating` package)
await Floating().enable(ImmediatePiP());
_controller.notifyPipEntered();   // hides controls overlay

// When PiP window is closed:
_controller.notifyPipExited();
```

### iOS (AVPictureInPictureController)

Wire `AVPictureInPictureController` inside a `FlutterPlatformView` or via a
method channel. Call `notifyPipEntered()` / `notifyPipExited()` from the
channel callback.

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

## 11. Configuration reference

| `PlayerConfig` field            | Default          | Description                                        |
|---------------------------------|------------------|----------------------------------------------------|
| `autoPlay`                      | `true`           | Start playback immediately after `open()`         |
| `loop`                          | `false`          | Loop at completion                                 |
| `initialSpeed`                  | `1.0`            | Playback speed (0.25–4.0)                         |
| `initialVolume`                 | `1.0`            | Volume (0.0–1.0)                                   |
| `bufferSize`                    | 32 MB            | Native network buffer in bytes                    |
| `enableHardwareAcceleration`    | `true`           | Platform GPU decoding                              |
| `useWakelock`                   | `true`           | Keep screen on during playback                    |
| `controlsTimeoutSeconds`        | `4`              | Seconds before controls auto-hide                 |
| `showBufferingIndicator`        | `true`           | Show spinner while buffering                      |
| `accentColor`                   | `Color(0xFFE50914)` | Progress bar + UI accent                       |
| `aspectRatio`                   | `null`           | Force canvas ratio (null = stream's native ratio) |
