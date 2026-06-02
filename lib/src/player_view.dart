import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'controller.dart';
import 'models/player_config.dart';
import 'models/video_fit.dart';
import 'platform.dart';
import 'widgets/controls_overlay.dart';
import 'widgets/error_overlay.dart';

BoxFit _boxFitOf(VideoFit fit) => switch (fit) {
      VideoFit.contain => BoxFit.contain,
      VideoFit.cover => BoxFit.cover,
      VideoFit.fill => BoxFit.fill,
    };

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

class _PlayerViewState extends State<PlayerView> with WindowListener {
  bool _isFullscreen = false;

  PlayerConfig get _cfg => widget.config ?? widget.controller.config;

  @override
  void initState() {
    super.initState();
    // Listen to OS-level fullscreen transitions (green button, Cmd+Ctrl+F,
    // Esc in fullscreen) so our state stays in sync even when the user
    // exits fullscreen without pressing our button.
    if (isDesktopPlatform) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (isDesktopPlatform) windowManager.removeListener(this);
    super.dispose();
  }

  // Called by window_manager when macOS/Windows exits native fullscreen.
  @override
  void onWindowLeaveFullScreen() {
    if (mounted && _isFullscreen) setState(() => _isFullscreen = false);
  }

  // Called when the OS enters fullscreen (e.g. user presses the green button).
  @override
  void onWindowEnterFullScreen() {
    if (mounted && !_isFullscreen) setState(() => _isFullscreen = true);
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

    if (isDesktopPlatform) {
      // On macOS/Windows/Linux: let the OS manage the window.
      await windowManager.setFullScreen(true);
    } else {
      // On mobile: lock to landscape + hide system UI, then push a covering route.
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
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
  }

  Future<void> _exitFullscreen() async {
    if (isDesktopPlatform) {
      await windowManager.setFullScreen(false);
    } else {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (mounted) setState(() => _isFullscreen = false);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video canvas — shared between embedded and _FullscreenRoute
// ─────────────────────────────────────────────────────────────────────────────

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
            ListenableBuilder(
              listenable: controller,
              builder: (_, _) => Video(
                controller: controller.videoController,
                controls: NoVideoControls,
                fit: _boxFitOf(controller.videoFit),
                fill: Colors.black,
                subtitleViewConfiguration:
                    config.subtitleViewConfiguration ??
                        const SubtitleViewConfiguration(),
              ),
            ),

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
    return Positioned.fill(child: img);
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
