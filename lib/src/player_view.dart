import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'models/player_config.dart';
import 'platform.dart';
import 'widgets/controls_overlay.dart';
import 'widgets/error_overlay.dart';

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
      await _exitFullscreen();
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
  }

  Future<void> _exitFullscreen() async {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    // Empty list = restore system default (honours the user's rotation lock).
    await SystemChrome.setPreferredOrientations([]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (mounted) setState(() => _isFullscreen = false);
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
            ListenableBuilder(
              listenable: controller,
              builder: (_, _) {
                final url = controller.currentPosterUrl;
                if (url == null) return const SizedBox.shrink();
                return AnimatedOpacity(
                  opacity: controller.posterVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 350),
                  child: _PosterOverlay(url: url),
                );
              },
            ),

            // ── 2. Buffering spinner ───────────────────────────────────────
            if (config.showBufferingIndicator)
              ListenableBuilder(
                listenable: controller,
                builder: (_, _) {
                  final show = controller.isBuffering || controller.isLoading;
                  return show
                      ? const _BufferingIndicator()
                      : const SizedBox.shrink();
                },
              ),

            // ── 3. Error overlay ───────────────────────────────────────────
            ListenableBuilder(
              listenable: controller,
              builder: (ctx, _) {
                if (!controller.hasError) return const SizedBox.shrink();
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
            ListenableBuilder(
              listenable: controller,
              builder: (_, _) {
                if (controller.hasError || controller.pipActive) {
                  return const SizedBox.shrink();
                }
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
