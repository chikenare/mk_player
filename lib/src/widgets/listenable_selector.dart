import 'package:flutter/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ListenableSelector
// ─────────────────────────────────────────────────────────────────────────────

/// Like [ListenableBuilder], but [builder] runs only when [selector] returns a
/// value that differs (by `==`) from the previous one — instead of on every
/// notification.
///
/// The player controller notifies ~3×/second during playback (the 300ms
/// position tick). Wrapping a position-independent subtree in a plain
/// [ListenableBuilder] rebuilds it on every one of those ticks; a
/// [ListenableSelector] keeps it stable in between, so only the pieces that
/// truly depend on the tick re-render. Use it to gate visibility flags
/// (hasError, buffering) and rarely-changing UI (track lists, speed label).
class ListenableSelector<T> extends StatefulWidget {
  final Listenable listenable;
  final T Function() selector;
  final Widget Function(BuildContext, T) builder;

  const ListenableSelector({
    super.key,
    required this.listenable,
    required this.selector,
    required this.builder,
  });

  @override
  State<ListenableSelector<T>> createState() => _ListenableSelectorState<T>();
}

class _ListenableSelectorState<T> extends State<ListenableSelector<T>> {
  late T _value = widget.selector();

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onChange);
  }

  @override
  void didUpdateWidget(ListenableSelector<T> old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_onChange);
      widget.listenable.addListener(_onChange);
      _value = widget.selector();
    }
  }

  void _onChange() {
    final next = widget.selector();
    if (next != _value) setState(() => _value = next);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
