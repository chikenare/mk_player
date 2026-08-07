import 'package:flutter/widgets.dart';

import '../models/tv_mode.dart';

/// Whether the focus-driven (TV) chrome should be shown for [mode].
///
/// In [TvMode.auto] this follows Flutter's own input heuristic: the focus
/// highlight mode is `touch` until the first key event arrives and `traditional`
/// from then on — i.e. it flips the instant a remote or keyboard is used.
bool resolveTvChrome(TvMode mode, [FocusHighlightMode? highlight]) {
  return switch (mode) {
    TvMode.enabled => true,
    TvMode.disabled => false,
    TvMode.auto =>
      (highlight ?? FocusManager.instance.highlightMode) ==
          FocusHighlightMode.traditional,
  };
}

/// Rebuilds [builder] whenever the TV chrome turns on or off.
///
/// Used by the pieces that live outside the controls overlay's own state (the
/// modal sheets), which have no other way to learn that a remote took over.
class TvChromeBuilder extends StatefulWidget {
  final TvMode mode;
  final Widget Function(BuildContext context, bool tvActive) builder;

  const TvChromeBuilder({
    super.key,
    required this.mode,
    required this.builder,
  });

  @override
  State<TvChromeBuilder> createState() => _TvChromeBuilderState();
}

class _TvChromeBuilderState extends State<TvChromeBuilder> {
  late bool _active = resolveTvChrome(widget.mode);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void didUpdateWidget(covariant TvChromeBuilder old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) _sync(resolveTvChrome(widget.mode));
  }

  void _onHighlightMode(FocusHighlightMode mode) =>
      _sync(resolveTvChrome(widget.mode, mode));

  void _sync(bool active) {
    if (!mounted || active == _active) return;
    setState(() => _active = active);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _active);
}
