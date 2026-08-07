import 'package:flutter/material.dart';

/// Full-screen error state shown when the player encounters an unrecoverable
/// stream failure (expired token, network loss, unsupported codec, etc.).
///
/// Provides a [onRetry] callback so the host or the controls layer can trigger
/// a re-open of the source without tearing down the widget tree.
class PlayerErrorOverlay extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  /// Puts the initial focus on "Try Again" so a remote has somewhere to go —
  /// the controls overlay (and its key handling) is gone while an error shows.
  final bool autofocusRetry;

  const PlayerErrorOverlay({
    super.key,
    this.message,
    this.onRetry,
    this.onBack,
    this.autofocusRetry = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Stack(
        children: [
          // ── Centred error content ────────────────────────────────────────
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.white54,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Playback Error',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (message != null && message!.isNotEmpty)
                    Text(
                      _sanitise(message!),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  const SizedBox(height: 32),
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      autofocus: autofocusRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Try Again'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white12,
                        // Visible from the sofa: the focused state is a filled
                        // pill, not a tint nobody can see across a room.
                        overlayColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Back button — always reachable regardless of player state ────
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                color: Colors.white70,
                iconSize: 20,
                tooltip: 'Go back',
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Strip raw libmpv error prefixes so the message is readable to end users.
  static String _sanitise(String raw) {
    const prefixes = ['ffmpeg/', 'mpv/', '[lavf]', 'Exception: '];
    var out = raw;
    for (final p in prefixes) {
      if (out.startsWith(p)) out = out.substring(p.length);
    }
    // Capitalise first letter.
    if (out.isNotEmpty) out = out[0].toUpperCase() + out.substring(1);
    return out;
  }
}
