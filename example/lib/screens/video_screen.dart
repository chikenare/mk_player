import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mk_player/mk_player.dart';

/// Full-screen video screen that wraps [PlayerView].
///
/// Creates a [CustomPlayerController], opens [source], and disposes on pop.
class VideoScreen extends StatefulWidget {
  final PlayerSource source;

  const VideoScreen({super.key, required this.source});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final CustomPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CustomPlayerController(
      config: const PlayerConfig(
        autoPlay: true,
        useWakelock: true,
        autoOrientation: true,
        accentColor: Color(0xFFE50914),
        fullscreenOrientations: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        controlsTimeoutSeconds: 4,
      ),
    );
    _controller.open(widget.source);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Player fills the full body
          PlayerView(controller: _controller),

          // Emergency back button — only shown while loading (before any
          // overlay appears). The error overlay has its own back button, so
          // we must NOT show this one when hasError to avoid duplication.
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (!_controller.isLoading) return const SizedBox.shrink();
              return SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: Colors.white70,
                      iconSize: 20,
                      tooltip: 'Go back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              );
            },
          ),

          _DebugBanner(controller: _controller),
        ],
      ),
    );
  }
}

// ── Debug overlay (visible only in debug builds) ──────────────────────────────

class _DebugBanner extends StatelessWidget {
  final CustomPlayerController controller;
  const _DebugBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    // kDebugMode is a compile-time constant — tree-shaken in release builds.
    if (!const bool.fromEnvironment('dart.vm.product', defaultValue: false)) {
      return Positioned(
        bottom: 88,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'state: ${controller.state.name}  '
                  'pos: ${controller.position.inSeconds}s  '
                  'audio: ${controller.audioTracks.length}  '
                  'sub: ${controller.subtitleTracks.length}  '
                  'video: ${controller.videoTracks.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
