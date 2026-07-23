import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'models/player_config.dart';
import 'platform.dart';
import 'widgets/controls_overlay.dart';
import 'widgets/error_overlay.dart';
import 'widgets/listenable_selector.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlayerView
// ─────────────────────────────────────────────────────────────────────────────

class PlayerView extends StatefulWidget {
  final CustomPlayerController controller;
  final PlayerConfig? config;

  const PlayerView({
    super.key,
    required this.controller,
    this.config,
  });

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  bool _isFullscreen = false;

  PlayerConfig get _cfg => widget.config ?? widget.controller.config;

  @override
  void initState() {
    super.initState();
    _initMobileChrome();
  }

  void _initMobileChrome() {
    if (!isMobilePlatform) return;

    // Immersive: hide the status & navigation bars while the player is shown.
    // immersiveSticky lets the user swipe them back temporarily.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!_cfg.autoOrientation) return;

    final explicit = _cfg.fullscreenOrientations;
    if (explicit != null) {
      // Explicit list provided — apply immediately.
      SystemChrome.setPreferredOrientations(explicit);
    } else {
      // Auto-detect: wait for videoParams to arrive before applying.
      widget.controller.addListener(_onControllerForOrientation);
    }
  }

  void _onControllerForOrientation() {
    if (!widget.controller.videoParamsReceived) return;
    widget.controller.removeListener(_onControllerForOrientation);
    final orientations = widget.controller.isPortraitVideo
        ? [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
    SystemChrome.setPreferredOrientations(orientations);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerForOrientation);
    if (isMobilePlatform) {
      // Restore the system bars and default orientation when leaving the player.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (_cfg.autoOrientation) {
        SystemChrome.setPreferredOrientations([]);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _VideoCanvas(
      controller: widget.controller,
      config: _cfg,
      isFullscreen: _isFullscreen,
      onToggleFullscreen: _toggleFullscreen,
    );
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      _exitFullscreen();
    } else {
      await _enterFullscreen();
    }
  }

  Future<void> _enterFullscreen() async {
    if (!mounted) return;
    setState(() => _isFullscreen = true);

    // Lock to the video's natural orientation + hide system UI, then push a
    // covering route. Allowing both orientations of the same axis lets the
    // device auto-rotate (e.g. landscapeLeft ↔ landscapeRight) without exiting.
    final orientations = _cfg.fullscreenOrientations ??
        (widget.controller.isPortraitVideo
            ? [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
            : [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]);
    await SystemChrome.setPreferredOrientations(orientations);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!mounted) return;
    await Navigator.of(context).push(
      _FullscreenRoute(
        playerController: widget.controller,
        playerConfig: _cfg,
        onExit: _exitFullscreen,
      ),
    );
    // Runs however the route was popped — the exit-fullscreen button OR the
    // system back gesture — so orientation and state are always restored.
    // Empty list = restore system default (honours the user's rotation lock).
    await SystemChrome.setPreferredOrientations([]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (mounted) setState(() => _isFullscreen = false);
  }

  void _exitFullscreen() {
    // Restoration happens in _enterFullscreen when the pushed route resolves.
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video canvas — shared between embedded and _FullscreenRoute
// ─────────────────────────────────────────────────────────────────────────────

// The [BetterPlayer] surface is a stable, direct child of the Stack — never
// wrapped in a ListenableBuilder — so it is not rebuilt on every position tick.
// Fit changes are handled internally by better_player via setOverriddenFit.
class _VideoCanvas extends StatelessWidget {
  final CustomPlayerController controller;
  final PlayerConfig config;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  const _VideoCanvas({
    required this.controller,
    required this.config,
    required this.isFullscreen,
    this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    Widget canvas = ClipRect(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. Video surface ───────────────────────────────────────────
            BetterPlayer(controller: controller.betterPlayerController),

            // ── 1.5. Poster — fades out on first decoded frame ────────────
            // Selector: rebuilds only when the (url, visible) pair flips — not
            // on every 300ms position tick.
            ListenableSelector<(String?, bool)>(
              listenable: controller,
              selector: () =>
                  (controller.currentPosterUrl, controller.posterVisible),
              builder: (_, value) {
                final (url, visible) = value;
                if (url == null) return const SizedBox.shrink();
                return AnimatedOpacity(
                  opacity: visible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 350),
                  child: _PosterOverlay(url: url),
                );
              },
            ),

            // ── 2. Buffering spinner ───────────────────────────────────────
            if (config.showBufferingIndicator)
              ListenableSelector<bool>(
                listenable: controller,
                selector: () => controller.isBuffering || controller.isLoading,
                builder: (_, show) => show
                    ? const _BufferingIndicator()
                    : const SizedBox.shrink(),
              ),

            // ── 3. Error overlay ───────────────────────────────────────────
            ListenableSelector<bool>(
              listenable: controller,
              selector: () => controller.hasError,
              builder: (ctx, hasError) {
                if (!hasError) return const SizedBox.shrink();
                return PlayerErrorOverlay(
                  message: controller.errorMessage,
                  onRetry: controller.retry,
                  onBack: Navigator.of(ctx).canPop()
                      ? () => Navigator.of(ctx).pop()
                      : null,
                );
              },
            ),

            // ── 4. Controls overlay ────────────────────────────────────────
            // The heavy controls subtree must NOT rebuild on every position
            // tick. Position-dependent pieces (progress bar, time, play/pause
            // icon) have their own fine-grained ListenableBuilders inside the
            // overlay; here we only need to gate visibility on hasError/pip,
            // which flip rarely. A ListenableSelector keeps the overlay stable in
            // between, eliminating the ~3×/second full-tree rebuild that was
            // competing with video compositing on the UI thread.
            ListenableSelector<bool>(
              listenable: controller,
              selector: () => controller.hasError || controller.pipActive,
              builder: (_, hidden) {
                if (hidden) return const SizedBox.shrink();
                return PlayerControlsOverlay(
                  controller: controller,
                  config: config,
                  isFullscreen: isFullscreen,
                  onToggleFullscreen: onToggleFullscreen,
                );
              },
            ),
          ],
        ),
      ),
    );

    if (config.aspectRatio != null) {
      canvas = AspectRatio(aspectRatio: config.aspectRatio!, child: canvas);
    }

    return canvas;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Poster overlay
// ─────────────────────────────────────────────────────────────────────────────

class _PosterOverlay extends StatelessWidget {
  final String url;
  const _PosterOverlay({required this.url});

  @override
  Widget build(BuildContext context) {
    Widget img;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      img = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else if (url.startsWith('assets/')) {
      img = Image.asset(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else {
      img = Image.file(
        File(url),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    // NOTE: not a Positioned — this widget is nested under AnimatedOpacity, not
    // directly inside the Stack. SizedBox.expand fills the (already tight)
    // constraints handed down from the Stack.
    return SizedBox.expand(child: img);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Buffering indicator
// ─────────────────────────────────────────────────────────────────────────────

class _BufferingIndicator extends StatelessWidget {
  const _BufferingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen route (mobile only)
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenRoute extends PageRoute<void> {
  final CustomPlayerController playerController;
  final PlayerConfig playerConfig;
  final VoidCallback onExit;

  _FullscreenRoute({
    required this.playerController,
    required this.playerConfig,
    required this.onExit,
  }) : super(fullscreenDialog: false);

  @override
  Color get barrierColor => Colors.black;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return FadeTransition(
      opacity: animation,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _VideoCanvas(
          controller: playerController,
          config: playerConfig,
          isFullscreen: true,
          onToggleFullscreen: onExit,
        ),
      ),
    );
  }
}
