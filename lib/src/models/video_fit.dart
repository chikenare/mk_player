/// How the video is scaled inside the player canvas.
///
/// Toggle at runtime with the aspect-ratio button (desktop) or a pinch gesture
/// (mobile).
enum VideoFit {
  /// Letterbox — fit the whole frame inside the view (default, no cropping).
  contain,

  /// Zoom to fill the view, cropping the overflow (removes black bars).
  cover,

  /// Stretch to fill the view, ignoring the aspect ratio.
  fill,
}
