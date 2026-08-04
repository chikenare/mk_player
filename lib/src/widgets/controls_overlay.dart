import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models/player_config.dart';
import '../models/video_fit.dart';
import '../platform.dart';
import 'listenable_selector.dart';
import 'progress_bar.dart';
import 'settings_sheet.dart';

String _fitLabel(VideoFit fit) => switch (fit) {
      VideoFit.contain => 'Fit',
      VideoFit.cover => 'Zoom',
      VideoFit.fill => 'Stretch',
    };

// ─────────────────────────────────────────────────────────────────────────────
// PlayerControlsOverlay
// ─────────────────────────────────────────────────────────────────────────────

class PlayerControlsOverlay extends StatefulWidget {
  final CustomPlayerController controller;
  final PlayerConfig config;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  /// Opens Picture-in-Picture. Null hides the PiP button entirely.
  final VoidCallback? onEnterPip;

  const PlayerControlsOverlay({
    super.key,
    required this.controller,
    required this.config,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.onEnterPip,
  });

  @override
  State<PlayerControlsOverlay> createState() => _PlayerControlsOverlayState();
}

enum _SeekSide { back, forward }

class _PlayerControlsOverlayState extends State<PlayerControlsOverlay>
    with SingleTickerProviderStateMixin {
  // ── Controls fade ──────────────────────────────────────────────────────────
  late final AnimationController _anim;
  late final Animation<double> _opacity;
  Timer? _hideTimer;
  bool _scrubbing = false;

  // ── Screen lock ────────────────────────────────────────────────────────────
  bool _locked = false;

  // ── Tap / multi-tap seek ─────────────────────────────────────────────────────
  // A single tap toggles the controls (deferred so it can be distinguished
  // from a seek gesture). Two or more quick taps on the same side accumulate a
  // seek: N taps = N × seekSeconds, committed when the burst ends — all without
  // opening the controls.
  Offset? _lastTapPos;
  Timer? _tapTimer;

  // Multi-tap seek burst
  int _burstCount = 0;
  _SeekSide? _burstSide;
  Duration _burstBase = Duration.zero;

  // After a manual hide (tap/click), ignore hover-to-show for a moment so the
  // same click's stray hover event doesn't immediately re-open the controls.
  DateTime? _suppressHoverUntil;

  // ── Seek flash ─────────────────────────────────────────────────────────────
  _SeekSide? _seekFlash;
  int _seekFlashSeconds = 0;
  Timer? _seekFlashTimer;

  // ── Pinch-to-zoom (mobile) ───────────────────────────────────────────────────
  double _lastScale = 1.0;
  String? _fitFlash;
  Timer? _fitFlashTimer;

  CustomPlayerController get ctrl => widget.controller;
  PlayerConfig get cfg => widget.config;

  @override
  void initState() {
    super.initState();
    // Start hidden: the player opens on a loading state, so the controls
    // should stay out of the way until the user taps to reveal them.
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 0.0,
    );
    _opacity = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
  }

  // ── Visibility ─────────────────────────────────────────────────────────────

  void _show() {
    _anim.forward();
    _scheduleHide();
  }

  void _scheduleHide() {
    if (cfg.controlsTimeoutSeconds <= 0) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(
      Duration(seconds: cfg.controlsTimeoutSeconds),
      _hideIfPlaying,
    );
  }

  void _hideIfPlaying() {
    if (!mounted || _scrubbing) return;
    // When locked, always allow the lock affordance to hide.
    if (_locked || ctrl.isPlaying) _anim.reverse();
  }

  void _toggleVisibility() {
    if (_anim.value > 0.5) {
      _hideTimer?.cancel();
      _anim.reverse();
      // Block the click's trailing hover event from re-opening the controls.
      _suppressHoverUntil =
          DateTime.now().add(const Duration(milliseconds: 500));
    } else {
      _show();
    }
  }

  void _onHover() {
    final until = _suppressHoverUntil;
    if (until != null && DateTime.now().isBefore(until)) return;
    _show();
  }

  // ── Lock ───────────────────────────────────────────────────────────────────

  void _lock() {
    setState(() => _locked = true);
    _show();
  }

  void _unlock() {
    setState(() => _locked = false);
    _show();
  }

  // ── Tap handling ───────────────────────────────────────────────────────────

  void _onTapUp(TapUpDetails details) => _lastTapPos = details.localPosition;

  void _onTap() {
    if (_scrubbing) return;
    // While locked, any tap just reveals the unlock affordance.
    if (_locked) {
      _toggleVisibility();
      return;
    }

    final width = context.size?.width ?? 1;
    final pos = _lastTapPos;
    final side = (pos != null && pos.dx < width / 2)
        ? _SeekSide.back
        : _SeekSide.forward;

    final continuing = _tapTimer?.isActive ?? false;
    _tapTimer?.cancel();

    if (continuing) {
      // Second or later tap → accumulate a seek burst (works open or closed,
      // never reveals the controls — only the ±total flash is shown).
      if (_burstCount == 0) {
        // Transition from a single pending tap into a burst: count both taps.
        _burstSide = side;
        _burstBase = ctrl.position;
        _burstCount = 2;
      } else if (_burstSide == side) {
        _burstCount++;
      } else {
        // Direction switched mid-burst → restart in the new direction.
        _burstSide = side;
        _burstBase = ctrl.position;
        _burstCount = 1;
      }
      _showSeekFlash(_burstSide!, _burstCount * cfg.seekSeconds);
    }

    // (Re)arm the window. On expiry: commit the accumulated seek if this was a
    // burst, otherwise treat it as a lone single tap → toggle controls.
    _tapTimer = Timer(const Duration(milliseconds: 250), () {
      _tapTimer = null;
      if (_burstCount > 0) {
        _commitBurstSeek();
      } else if (mounted) {
        _toggleVisibility();
      }
    });
  }

  void _commitBurstSeek() {
    final secs = _burstCount * cfg.seekSeconds;
    final delta =
        Duration(seconds: _burstSide == _SeekSide.back ? -secs : secs);
    ctrl.seek(_burstBase + delta); // seek() clamps to the valid range
    _burstCount = 0;
    _burstSide = null;
  }

  // ── Seek ───────────────────────────────────────────────────────────────────

  // Used by the on-screen skip buttons (single fixed jump).
  void _seekBy(Duration delta, _SeekSide side) {
    ctrl.seek(ctrl.position + delta); // seek() clamps to the valid range
    _showSeekFlash(side, delta.inSeconds.abs());
  }

  void _showSeekFlash(_SeekSide side, int seconds) {
    if (!mounted) return;
    setState(() {
      _seekFlash = side;
      _seekFlashSeconds = seconds;
    });
    _seekFlashTimer?.cancel();
    _seekFlashTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _seekFlash = null);
    });
  }

  // ── Pinch-to-zoom (mobile) ───────────────────────────────────────────────────

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_locked) return;
    if (d.pointerCount >= 2) _lastScale = d.scale;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_locked) return;
    final s = _lastScale;
    _lastScale = 1.0;
    if (s > 1.15) {
      ctrl.setVideoFit(VideoFit.cover);
      _flashFit('Zoom');
    } else if (s < 0.85) {
      ctrl.setVideoFit(VideoFit.contain);
      _flashFit('Fit');
    }
  }

  void _flashFit(String label) {
    if (!mounted) return;
    setState(() => _fitFlash = label);
    _fitFlashTimer?.cancel();
    _fitFlashTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _fitFlash = null);
    });
  }

  // ── Scrubbing ───────────────────────────────────────────────────────────────

  void _onScrubStart() {
    _scrubbing = true;
    _hideTimer?.cancel();
    _anim.forward();
  }

  void _onScrubEnd() {
    _scrubbing = false;
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _tapTimer?.cancel();
    _seekFlashTimer?.cancel();
    _fitFlashTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        onTap: _onTap,
        // Pinch-to-zoom on mobile only (disabled while locked).
        onScaleUpdate: isMobilePlatform ? _onScaleUpdate : null,
        onScaleEnd: isMobilePlatform ? _onScaleEnd : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Fading controls
            AnimatedBuilder(
              animation: _anim,
              builder: (_, child) => IgnorePointer(
                ignoring: _anim.isDismissed,
                child: Opacity(opacity: _opacity.value, child: child),
              ),
              child: _locked ? _buildLocked() : _buildControls(),
            ),
            // Seek flash badges — always visible (work while controls hidden,
            // so a double-tap seek shows ±seconds without revealing controls)
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _seekFlash == _SeekSide.back ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 160),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _SeekBadge(forward: false, seconds: _seekFlashSeconds),
                ),
              ),
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _seekFlash == _SeekSide.forward ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 160),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _SeekBadge(forward: true, seconds: _seekFlashSeconds),
                ),
              ),
            ),
            // Fit flash — always visible (pinch works while controls hidden)
            IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _fitFlash != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 160),
                  child: _FitBadge(label: _fitFlash ?? ''),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Locked overlay ──────────────────────────────────────────────────────────

  Widget _buildLocked() {
    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0x55000000)),
            ),
          ),
        ),
        Center(
          child: GestureDetector(
            onTap: _unlock,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(130),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 1.5),
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tap to unlock',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Full controls ─────────────────────────────────────────────────────────

  Widget _buildControls() {
    return Stack(
      children: [
        // Vignette
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.22, 0.62, 1.0],
                  colors: [
                    Color(0xCC000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xE6000000),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Top bar
        Positioned(
          top: 0, left: 0, right: 0,
          child: _TopBar(
            controller: ctrl,
            config: cfg,
            isFullscreen: widget.isFullscreen,
            onToggleFullscreen: widget.onToggleFullscreen,
            onLock: cfg.showLockButton ? _lock : null,
            onEnterPip: cfg.showPipButton ? widget.onEnterPip : null,
            // Aspect-ratio button: desktop/web only (mobile uses pinch).
            onCycleFit: isDesktopOrWeb
                ? () {
                    ctrl.cycleVideoFit();
                    _flashFit(_fitLabel(ctrl.videoFit));
                    _show();
                  }
                : null,
          ),
        ),

        // Centre row
        Center(
          child: _CentreRow(
            controller: ctrl,
            seekSeconds: cfg.seekSeconds,
            onActivity: _show,
            onRewind: () =>
                _seekBy(Duration(seconds: -cfg.seekSeconds), _SeekSide.back),
            onForward: () =>
                _seekBy(Duration(seconds: cfg.seekSeconds), _SeekSide.forward),
          ),
        ),

        // Bottom bar
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _BottomBar(
            controller: ctrl,
            config: cfg,
            onActivity: _show,
            onScrubStart: _onScrubStart,
            onScrubEnd: _onScrubEnd,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seek badge
// ─────────────────────────────────────────────────────────────────────────────

class _SeekBadge extends StatelessWidget {
  final bool forward;
  final int seconds;

  const _SeekBadge({required this.forward, required this.seconds});

  @override
  Widget build(BuildContext context) {
    final icon = forward
        ? Icons.fast_forward_rounded
        : Icons.fast_rewind_rounded;
    return Padding(
      padding: EdgeInsets.only(left: forward ? 0 : 24, right: forward ? 24 : 0),
      child: Container(
        width: 96,
        height: 96,
        decoration: const BoxDecoration(
          color: Color(0x66000000),
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 2),
            Text(
              '${seconds}s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fit flash badge
// ─────────────────────────────────────────────────────────────────────────────

class _FitBadge extends StatelessWidget {
  final String label;
  const _FitBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.aspect_ratio_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final CustomPlayerController controller;
  final PlayerConfig config;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onLock;
  final VoidCallback? onEnterPip;

  final VoidCallback? onCycleFit;

  const _TopBar({
    required this.controller,
    required this.config,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onLock,
    required this.onEnterPip,
    required this.onCycleFit,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(
          children: [
            if (isFullscreen)
              _IconBtn(
                icon: Icons.fullscreen_exit_rounded,
                size: 24,
                tooltip: 'Exit fullscreen',
                onPressed: onToggleFullscreen,
              )
            else if (Navigator.of(context).canPop())
              _IconBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                size: 20,
                onPressed: () => Navigator.of(context).pop(),
              ),

            if (config.showTitle && controller.currentTitle != null) ...[
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  controller.currentTitle!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                ),
              ),
            ] else
              const Spacer(),

            // Aspect ratio (desktop/web)
            if (onCycleFit != null)
              _IconBtn(
                icon: Icons.aspect_ratio_rounded,
                size: 22,
                tooltip: 'Aspect ratio',
                onPressed: onCycleFit,
              ),

            // Picture-in-Picture — only once the native side has confirmed the
            // device supports it (resolved shortly after the first frame).
            if (onEnterPip != null)
              ListenableSelector<bool>(
                listenable: controller,
                selector: () => controller.pipSupported,
                builder: (_, supported) => supported
                    ? _IconBtn(
                        icon: Icons.picture_in_picture_alt_rounded,
                        size: 22,
                        tooltip: 'Picture-in-Picture',
                        onPressed: onEnterPip,
                      )
                    : const SizedBox.shrink(),
              ),

            // Lock screen
            if (onLock != null)
              _IconBtn(
                icon: Icons.lock_outline_rounded,
                size: 22,
                tooltip: 'Lock screen',
                onPressed: onLock,
              ),

            // Fullscreen
            if (!isFullscreen && onToggleFullscreen != null)
              _IconBtn(
                icon: Icons.fullscreen_rounded,
                size: 24,
                tooltip: 'Fullscreen',
                onPressed: onToggleFullscreen,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Centre row — rewind · play/pause · forward
// ─────────────────────────────────────────────────────────────────────────────

class _CentreRow extends StatelessWidget {
  final CustomPlayerController controller;
  final int seekSeconds;
  final VoidCallback onActivity;
  final VoidCallback onRewind;
  final VoidCallback onForward;

  const _CentreRow({
    required this.controller,
    required this.seekSeconds,
    required this.onActivity,
    required this.onRewind,
    required this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SkipButton(
            seconds: seekSeconds,
            forward: false,
            onTap: () { onRewind(); onActivity(); }),
        const SizedBox(width: 28),
        _CentreButton(controller: controller, onActivity: onActivity),
        const SizedBox(width: 28),
        _SkipButton(
            seconds: seekSeconds,
            forward: true,
            onTap: () { onForward(); onActivity(); }),
      ],
    );
  }
}

class _CentreButton extends StatelessWidget {
  final CustomPlayerController controller;
  final VoidCallback onActivity;

  const _CentreButton({required this.controller, required this.onActivity});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (_, _) {
        final state = controller.state;
        IconData icon;
        VoidCallback? action;

        switch (state) {
          case MkPlayerState.playing:
          case MkPlayerState.buffering:
            icon = Icons.pause_rounded;
            action = () { controller.pause(); onActivity(); };
          case MkPlayerState.completed:
            icon = Icons.replay_rounded;
            action = () {
              controller.seek(Duration.zero);
              controller.play();
              onActivity();
            };
          default:
            icon = Icons.play_arrow_rounded;
            action = () { controller.play(); onActivity(); };
        }

        return GestureDetector(
          onTap: action,
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(120),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
            child: Icon(icon, color: Colors.white, size: 36),
          ),
        );
      },
    );
  }
}

class _SkipButton extends StatelessWidget {
  final int seconds;
  final bool forward;
  final VoidCallback onTap;

  const _SkipButton({
    required this.seconds,
    required this.forward,
    required this.onTap,
  });

  IconData get _icon => forward
      ? switch (seconds) {
          5 => Icons.forward_5_rounded,
          10 => Icons.forward_10_rounded,
          30 => Icons.forward_30_rounded,
          _ => Icons.forward_rounded,
        }
      : switch (seconds) {
          5 => Icons.replay_5_rounded,
          10 => Icons.replay_10_rounded,
          30 => Icons.replay_30_rounded,
          _ => Icons.replay_rounded,
        };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(100),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Icon(_icon, color: Colors.white, size: 24),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatefulWidget {
  final CustomPlayerController controller;
  final PlayerConfig config;
  final VoidCallback onActivity;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;

  const _BottomBar({
    required this.controller,
    required this.config,
    required this.onActivity,
    required this.onScrubStart,
    required this.onScrubEnd,
  });

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  bool _showRemaining = false;

  CustomPlayerController get ctrl => widget.controller;
  PlayerConfig get cfg => widget.config;

  @override
  Widget build(BuildContext context) {
    final showVolume = cfg.showVolumeControl ?? isDesktopOrWeb;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Progress + time ────────────────────────────────────────────
            // These depend on position/duration, which advance on every 300ms
            // tick, so this part legitimately rebuilds per tick.
            ListenableBuilder(
              listenable: ctrl,
              builder: (_, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlayerProgressBar(
                    position: ctrl.position,
                    duration: ctrl.duration,
                    buffered: ctrl.buffered,
                    accentColor: cfg.accentColor,
                    storyboard: ctrl.storyboard,
                    onScrubStart: widget.onScrubStart,
                    onScrubEnd: widget.onScrubEnd,
                    onSeek: ctrl.isLive
                        ? null
                        : (d) {
                            ctrl.seek(d);
                            widget.onActivity();
                          },
                  ),

                  // Time row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 2, 0),
                    child: Row(
                      children: [
                        Text(
                          formatDuration(ctrl.position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (ctrl.isLive)
                          const _LiveBadge()
                        else
                          GestureDetector(
                            onTap: () {
                              setState(() => _showRemaining = !_showRemaining);
                              widget.onActivity();
                            },
                            child: Text(
                              _showRemaining
                                  ? '  -${formatDuration(ctrl.remaining)}'
                                  : '  /  ${formatDuration(ctrl.duration)}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (showVolume)
                          _VolumeButton(
                            controller: ctrl,
                            onActivity: widget.onActivity,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Action buttons row (Netflix-style) ─────────────────────────
            // Track availability and the speed label change rarely, so a
            // selector keeps this row stable between ticks instead of
            // rebuilding it ~3×/second along with the progress bar.
            ListenableSelector<(bool, bool, double)>(
              listenable: ctrl,
              selector: () => (
                ctrl.audioTracks.length > 1,
                // Host actions (e.g. "search subtitles online") must stay
                // reachable even when the media carries no subtitle track.
                ctrl.hasSubtitles || cfg.subtitleActions.isNotEmpty,
                ctrl.speed,
              ),
              builder: (_, value) {
                final (showAudio, showSubs, speed) = value;
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      _ActionButton(
                        icon: Icons.speed_rounded,
                        label: speed == 1.0 ? 'Speed' : 'Speed · $speed×',
                        onTap: () {
                          widget.onActivity();
                          showSpeedSheet(context, ctrl);
                        },
                      ),
                      if (showAudio)
                        _ActionButton(
                          icon: Icons.multitrack_audio_rounded,
                          label: 'Audio',
                          onTap: () {
                            widget.onActivity();
                            showAudioSheet(context, ctrl);
                          },
                        ),
                      if (showSubs)
                        _ActionButton(
                          icon: Icons.closed_caption_rounded,
                          label: 'Subtitles',
                          onTap: () {
                            widget.onActivity();
                            showSubtitleSheet(context, ctrl, config: cfg);
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action button (icon + label) — Netflix-style bottom control
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live badge
// ─────────────────────────────────────────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFE50914),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'LIVE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Volume toggle + slider
// ─────────────────────────────────────────────────────────────────────────────

class _VolumeButton extends StatefulWidget {
  final CustomPlayerController controller;
  final VoidCallback onActivity;

  const _VolumeButton({required this.controller, required this.onActivity});

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final muted = widget.controller.muted;
    final vol = widget.controller.rawVolume;
    final pct = ((muted ? 0.0 : vol) * 100).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconBtn(
          icon: muted || vol == 0
              ? Icons.volume_off_rounded
              : vol < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
          size: 22,
          compact: true,
          onPressed: () {
            setState(() => _expanded = !_expanded);
            if (!_expanded) widget.controller.toggleMute();
            widget.onActivity();
          },
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: _expanded ? 80 : 0,
          curve: Curves.easeOut,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: muted ? 0 : vol,
              onChanged: (v) {
                widget.controller.setVolume(v);
                if (widget.controller.muted && v > 0) {
                  widget.controller.toggleMute();
                }
                widget.onActivity();
              },
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: _expanded ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: IgnorePointer(
            ignoring: !_expanded,
            child: SizedBox(
              width: 32,
              child: Text(
                '$pct%',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared icon button
// ─────────────────────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final String? tooltip;
  final bool compact;
  final VoidCallback? onPressed;

  const _IconBtn({
    required this.icon,
    required this.size,
    this.tooltip,
    this.compact = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      color: Colors.white,
      iconSize: size,
      tooltip: tooltip,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      onPressed: onPressed,
    );
  }
}
