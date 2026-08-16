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

Tracks use `better_player` types, re-exported from `mk_player`
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
      apiUrl: 'https://api.example.com/api/telemetry',
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

### Reporting to your own API instead

The player measures the session; where it is reported is a separate decision.
`onPlaybackEvent` gives you every measured event so you can send it yourself,
with no `TelemetryConfig` involved:

```dart
_controller = CustomPlayerController(
  config: PlayerConfig(
    onPlaybackEvent: (PlaybackEvent event) {
      // event.type: start | progress | end | error
      // event.sessionId, .contentId, .episodeId, .positionSeconds,
      // .secondsWatchedDelta, .stallCountDelta, .stalledSecondsDelta,
      // .startupMs, .resolution — every counter a delta since the last event.
      myAnalytics.enqueue(event);
    },
  ),
);
```

* Nothing is queued, persisted or posted anywhere: what you do with the event
  is entirely yours. The on-disk queue and the retries only exist for the
  built-in reporter.
* Set both `telemetry` and `onPlaybackEvent` and one measurement feeds both —
  each event arrives at each side **once, and identical** (same `sessionId`,
  same deltas).
* **A source without `contentId` produces no events**, callback included.
* Keep the callback quick — it runs while the event is measured. An exception
  thrown inside it is caught and logged; it never breaks playback nor the
  built-in queue.

`PlaybackEvent` carries no wire format of its own; the JSON payload of §11 is
built by the telemetry layer. The old names `TelemetryEvent` /
`TelemetryEventType` still work as aliases.

---

## 12. Android TV / remote control

### Manifest

```xml
<manifest ...>
    <!-- Both optional: the same APK still installs on phones -->
    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>
    <uses-feature android:name="android.software.leanback" android:required="false"/>

    <application android:banner="@drawable/tv_banner" ...>   <!-- 320×180 -->
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

### Player

```dart
_controller = CustomPlayerController(
  config: PlayerConfig(
    tvMode: TvMode.enabled,       // focus skin on from the first frame
    autoOrientation: false,       // a TV does not rotate
    // Optional: wire the remote's ⏮ / ⏭ keys to your own playlist.
    onSkipNext: _playNextEpisode,
    onSkipPrevious: _playPreviousEpisode,
  ),
);
```

`TvMode.auto` (the default) also works on a TV — it just waits for the first
key press to switch the skin on. Pass `TvMode.enabled` when you know you are on
a TV so the controls are navigable before anything is pressed, and
`TvMode.disabled` to opt out of key handling entirely.

### What the remote does

| Key | Controls hidden | Controls visible |
|---|---|---|
| ← / → | reveal + scrub | scrub (seek bar) · move focus (button) |
| ↑ / ↓ | reveal | move focus between rows |
| OK | reveal | play/pause (seek bar) · press the button |
| Back | closes the player | hides the controls |
| ▶⏸ ▶ ⏸ ⏹ | act | act |
| ⏪ ⏩ | scrub | scrub |
| ⏮ ⏭ | `onSkipPrevious` / `onSkipNext`, else scrub | idem |

Holding ← / → accelerates (1× → 6× `seekSeconds`) and commits one seek ~400 ms
after the last press, previewing the target on the bar meanwhile.

Volume, home and channel keys are never intercepted — they stay with the
system, which is what a TV user expects.

### The TV layout

While the TV skin is on, the controls drop every button the remote already
covers — each one is a focus stop the user has to travel through:

| Dropped | Replaced by |
|---|---|
| ◀ back arrow (top-left) | the **Back** key (controls first, then the player) |
| ⏪ / ⏩ ±`seekSeconds` | ← / → scrubbing; the centre play/pause stays as a state indicator, out of the focus order |
| **Speed** | nothing on screen — `controller.setSpeed()` for a host-supplied control |
| 🔒 **Lock** | nothing: a locked player is a trap without a touchscreen |
| ⛶ **Fullscreen** | nothing: the video already fills the screen and a TV has no window or orientation to manage |

**Audio** and **Subtitles** become a single **Audio & Subtitles** button that
opens a panel pinned to the right edge: one column per type, each as tall as its
own entries, ↑/↓ inside a column and ←/→ between them. Focus opens on the track
that is playing; OK applies it and keeps the panel open (the check mark moves),
Back closes it. `subtitleActions` sit under the subtitle column and still close
the panel before running.

The layout follows the TV skin, so a `TvMode.auto` build swaps to it the moment a
remote is used and swaps back for a finger. Of the four, only ⛶ can be forced
back on (`showFullscreenButton: true`); `showLockButton`,
`showAspectRatioButton` and `showFullscreenButton` all still govern the touch
case as usual.

### Notes


* `showControls: false` still turns everything off, key handling included, for
  hosts that ship their own focusable TV layout.
* Nothing here is Android-only in Dart terms: the same keys work from a
  keyboard on desktop, which is the quickest way to test the flows.

---

## 13. Configuration reference

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
| `accentColor`                   | `Color(0xFFE50914)` | Progress bar colour (focus/selection are white) |
| `subtitlesConfiguration`        | `BetterPlayerSubtitlesConfiguration()` | Subtitle appearance: font size/colour/family, outline, background, paddings, alignment |
| `aspectRatio`                   | `null`           | Force canvas ratio (null = stream's native ratio) |
| `showAspectRatioButton`         | `null`           | Fit/Zoom/Stretch button; `null` = auto (desktop/web/TV), or force `true`/`false` |
| `showFullscreenButton`          | `null`           | ⛶ fullscreen button; `null` = auto (off while the TV skin is on), or force `true`/`false` |
| `tvMode`                        | `TvMode.auto`    | Remote/D-pad handling: `auto` / `enabled` / `disabled` (see §12) |
| `onSkipNext`                    | `null`           | Remote ⏭ key; falls back to a forward seek (see §12) |
| `onSkipPrevious`                | `null`           | Remote ⏮ key; falls back to a backward seek (see §12) |
| `telemetry`                     | `null`           | `TelemetryConfig` for playback reporting (see §11) |
| `onPlaybackEvent`               | `null`           | `void Function(PlaybackEvent)` — every measured playback event, to report it to your own API (see §11) |
