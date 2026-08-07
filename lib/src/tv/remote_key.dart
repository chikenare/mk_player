import 'package:flutter/services.dart';

/// The remote-control / D-pad gestures the player understands.
///
/// Keys that are not mapped here (volume, channel, the launcher keys, …) are
/// deliberately left to the system.
enum RemoteKey {
  left,
  right,
  up,
  down,
  select,
  back,
  playPause,
  play,
  pause,
  stop,
  fastForward,
  rewind,
  next,
  previous,
}

/// Maps a logical key to the player gesture it stands for, or null when the
/// player has no business handling it.
///
/// Covers the three remotes an Android TV app actually meets: the plain D-pad
/// (arrows + center), the media remote (transport keys) and a game controller.
RemoteKey? mapRemoteKey(LogicalKeyboardKey key) {
  // ── D-pad ───────────────────────────────────────────────────────────────
  if (key == LogicalKeyboardKey.arrowLeft) return RemoteKey.left;
  if (key == LogicalKeyboardKey.arrowRight) return RemoteKey.right;
  if (key == LogicalKeyboardKey.arrowUp) return RemoteKey.up;
  if (key == LogicalKeyboardKey.arrowDown) return RemoteKey.down;
  if (key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.gameButtonA) {
    return RemoteKey.select;
  }

  // ── Back ────────────────────────────────────────────────────────────────
  // Android usually routes its hardware back through the navigation channel
  // (handled by the PopScope in the controls overlay); these are the cases
  // that do arrive as key events — a keyboard, or a remote reporting BROWSER
  // BACK / gamepad B.
  if (key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.browserBack ||
      key == LogicalKeyboardKey.gameButtonB) {
    return RemoteKey.back;
  }

  // ── Transport ───────────────────────────────────────────────────────────
  if (key == LogicalKeyboardKey.mediaPlayPause ||
      key == LogicalKeyboardKey.gameButtonStart) {
    return RemoteKey.playPause;
  }
  if (key == LogicalKeyboardKey.mediaPlay) return RemoteKey.play;
  if (key == LogicalKeyboardKey.mediaPause) return RemoteKey.pause;
  if (key == LogicalKeyboardKey.mediaStop) return RemoteKey.stop;
  if (key == LogicalKeyboardKey.mediaFastForward) return RemoteKey.fastForward;
  if (key == LogicalKeyboardKey.mediaRewind) return RemoteKey.rewind;
  if (key == LogicalKeyboardKey.mediaTrackNext) return RemoteKey.next;
  if (key == LogicalKeyboardKey.mediaTrackPrevious) return RemoteKey.previous;

  return null;
}
