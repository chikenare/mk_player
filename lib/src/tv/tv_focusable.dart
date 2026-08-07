import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Builds the control; [focused] is true only while the widget holds focus
/// *and* the user is navigating with a remote/keyboard — never on a plain tap.
typedef TvFocusBuilder = Widget Function(BuildContext context, bool focused);

/// A control that works the same under a finger and under a D-pad.
///
/// On touch it is an ordinary tappable widget: [builder] is called with
/// `focused: false` and nothing about the existing UI changes. Once the user
/// picks up a remote, Flutter switches the focus highlight mode and the same
/// widget starts reporting focus so it can draw a ring.
///
/// Activation is bound to every key a "select" can arrive as — the D-pad
/// center reports as [LogicalKeyboardKey.select], which Flutter's default
/// shortcuts do not cover.
class TvFocusable extends StatefulWidget {
  final TvFocusBuilder builder;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Set false to keep the control tappable but out of the focus order.
  final bool canRequestFocus;

  final String? tooltip;

  const TvFocusable({
    super.key,
    required this.builder,
    this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.tooltip,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  static const Map<ShortcutActivator, Intent> _activators = {
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  };

  void _onHighlight(bool value) {
    if (!mounted || value == _focused) return;
    setState(() => _focused = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && widget.canRequestFocus;

    Widget child = FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: enabled,
      shortcuts: _activators,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      mouseCursor: widget.onPressed == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onShowFocusHighlight: _onHighlight,
      child: Semantics(
        button: true,
        enabled: widget.onPressed != null,
        child: widget.builder(context, enabled && _focused),
      ),
    );

    if (widget.onPressed != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: child,
      );
    }

    final tooltip = widget.tooltip;
    if (tooltip != null) child = Tooltip(message: tooltip, child: child);

    return child;
  }
}

/// The focus ring shared by every TV-navigable control.
///
/// Deliberately loud: it is read from three metres away, on top of moving
/// video, by someone who cannot see a cursor.
BoxDecoration tvFocusDecoration({
  required bool focused,
  required Color accentColor,
  BoxShape shape = BoxShape.circle,
  BorderRadius? borderRadius,
  Color? background,
}) {
  return BoxDecoration(
    color: focused ? accentColor.withAlpha(60) : background,
    // A BoxDecoration may not carry both a circle shape and a radius.
    shape: borderRadius != null ? BoxShape.rectangle : shape,
    borderRadius: borderRadius,
    border: focused
        ? Border.all(color: Colors.white, width: 2)
        : Border.all(color: Colors.transparent, width: 2),
    boxShadow: focused
        ? [BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 12)]
        : null,
  );
}
