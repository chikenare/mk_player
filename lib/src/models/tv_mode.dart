/// How the player adapts to being driven by a TV remote / D-pad.
///
/// "TV chrome" means the focus-driven skin: a visible focus ring on every
/// control, the seek bar taking focus so left/right scrubs, the lock button
/// hidden (there are no pocket taps on a sofa) and the controls autofocusing
/// when they appear.
enum TvMode {
  /// Handle remote/keyboard keys always, and turn the TV chrome on the moment
  /// the user actually presses one (Flutter switches
  /// [FocusManager.highlightMode] to `traditional` on the first key event).
  ///
  /// The default: a phone build behaves exactly as before, and the same build
  /// running on a TV becomes navigable as soon as the remote is used.
  auto,

  /// Always on. What an Android TV / leanback app should pass — the controls
  /// are focus-navigable from the very first frame, before any key is pressed.
  enabled,

  /// Off: no key handling, no focus ring, touch only.
  disabled,
}
