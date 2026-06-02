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
    if (isDesktopPlatform) windowManager.addListener(this);
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
      // On mobile: lock to the video's natural orientation + hide system UI,
      // then push a covering route.
      // Allowing both orientations of the same axis lets the device auto-rotate
      // (e.g. landscapeLeft ↔ landscapeRight) without exiting fullscreen.
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
  }

  Future<void> _exitFullscreen() async {
    if (isDesktopPlatform) {
      await windowManager.setFullScreen(false);
    } else {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      // Empty list = restore system default (honours the user's rotation lock).
      await SystemChrome.setPreferredOrientations([]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (mounted) setState(() => _isFullscreen = false);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video canvas — shared between embedded and _FullscreenRoute
// ─────────────────────────────────────────────────────────────────────────────

// StatefulWidget so the Video surface is stable and never wrapped in a
// ListenableBuilder. Rebuilding Video on every position tick (~60 Hz) causes
// Android to invalidate the native Texture, producing a permanent black screen.
// Only videoFit changes trigger a setState here.
class _VideoCanvas extends StatefulWidget {
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
  State<_VideoCanvas> createState() => _VideoCanvasState();
}

class _VideoCanvasState extends State<_VideoCanvas> {
  late BoxFit _fit;

  @override
  void initState() {
    super.initState();
    _fit = _boxFitOf(widget.controller.videoFit);
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void didUpdateWidget(_VideoCanvas old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
      _fit = _boxFitOf(widget.controller.videoFit);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    final newFit = _boxFitOf(widget.controller.videoFit);
    if (newFit != _fit) setState(() => _fit = newFit);
  }

  @override
  Widget build(BuildContext context) {
    Widget canvas = ClipRect(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. Video surface ───────────────────────────────────────────
            // Direct child — never rebuilt by the controller's notification
            // stream. Only _fit changes (rare) cause a setState above.
            Video(
              controller: widget.controller.videoController,
              controls: NoVideoControls,
              fit: _fit,
              fill: Colors.black,
              subtitleViewConfiguration:
                  widget.config.subtitleViewConfiguration ??
                      const SubtitleViewConfiguration(),
            ),

            // ── 1.5. Poster — fades out on first decoded frame ────────────
            ListenableBuilder(
              listenable: widget.controller,
              builder: (_, _) {
                final url = widget.controller.currentPosterUrl;
                if (url == null) return const SizedBox.shrink();
                return AnimatedOpacity(
                  opacity: widget.controller.posterVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 350),
                  child: _PosterOverlay(url: url),
                );
              },
            ),

            // ── 2. Buffering spinner ───────────────────────────────────────
            if (widget.config.showBufferingIndicator)
              ListenableBuilder(
                listenable: widget.controller,
                builder: (_, _) {
                  final show =
                      widget.controller.isBuffering ||
                      widget.controller.isLoading;
                  return show
                      ? const _BufferingIndicator()
                      : const SizedBox.shrink();
                },
              ),

            // ── 3. Error overlay ───────────────────────────────────────────
            ListenableBuilder(
              listenable: widget.controller,
              builder: (ctx, _) {
                if (!widget.controller.hasError) return const SizedBox.shrink();
                return PlayerErrorOverlay(
                  message: widget.controller.errorMessage,
                  onRetry: widget.controller.retry,
                  onBack: Navigator.of(ctx).canPop()
                      ? () => Navigator.of(ctx).pop()
                      : null,
                );
              },
            ),

            // ── 4. Controls overlay ────────────────────────────────────────
            ListenableBuilder(
              listenable: widget.controller,
              builder: (_, _) {
                if (widget.controller.hasError || widget.controller.pipActive) {
                  return const SizedBox.shrink();
                }
                return PlayerControlsOverlay(
                  controller: widget.controller,
                  config: widget.config,
                  isFullscreen: widget.isFullscreen,
                  onToggleFullscreen: widget.onToggleFullscreen,
                );
              },
            ),
          ],
        ),
      ),
    );

    if (widget.config.aspectRatio != null) {
      canvas = AspectRatio(
          aspectRatio: widget.config.aspectRatio!, child: canvas);
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
