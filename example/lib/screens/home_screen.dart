import 'package:flutter/material.dart';
import 'package:mk_player/mk_player.dart';

import 'video_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Preset sources for quick testing
// ─────────────────────────────────────────────────────────────────────────────

class _Preset {
  final String title;
  final String subtitle;
  final IconData icon;
  final PlayerSource source;

  const _Preset({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.source,
  });
}

final _presets = <_Preset>[
  _Preset(
    title: 'HLS — Big Buck Bunny',
    subtitle: 'Mux test stream · multi-bitrate · .m3u8',
    icon: Icons.stream,
    source: PlayerSource.network(
      startAt: Duration(seconds: 30),
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      title: 'Big Buck Bunny (HLS)',
      storyboardUrl:
          'https://nukevideo-api.tibibyte.com/videos/01KSXW84FGCVNA10RB84GT1W0Z/storyboard.vtt',
    ),
  ),
  _Preset(
    title: 'DASH — Big Buck Bunny',
    subtitle: 'Akamai test stream · .mpd',
    icon: Icons.dashboard_rounded,
    source: PlayerSource.network(
      'https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd',
      title: 'Big Buck Bunny (DASH)',
    ),
  ),
  _Preset(
    title: 'MP4 + poster + startAt',
    subtitle: 'Poster image · resumes at 0:30',
    icon: Icons.movie_outlined,
    source: PlayerSource.network(
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      title: 'Big Buck Bunny (MP4)',
      posterUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
      startAt: const Duration(seconds: 30),
    ),
  ),
  _Preset(
    title: 'Storyboard test',
    subtitle: 'nukevideo · storyboard VTT thumbnails',
    icon: Icons.photo_library_outlined,
    source: PlayerSource.network(
      'https://nukevideo-api.tibibyte.com/videos/01KSXW84FGCVNA10RB84GT1W0Z/master.m3u8',
      title: 'Storyboard preview test',
      storyboardUrl:
          'https://nukevideo-api.tibibyte.com/videos/01KSXW84FGCVNA10RB84GT1W0Z/storyboard.vtt',
    ),
  ),
  _Preset(
    title: 'Elephants Dream (HLS)',
    subtitle: 'Multi-audio + subtitle tracks',
    icon: Icons.subtitles_outlined,
    source: PlayerSource.network(
      'https://playertest.longtailvideo.com/adaptive/elephants_dream_playlist/elephants_dream.m3u8',
      title: 'Elephants Dream',
    ),
  ),
  _Preset(
    title: 'Sintel (HLS)',
    subtitle: 'Blender Institute · HLS',
    icon: Icons.theaters_outlined,
    source: PlayerSource.network(
      'https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8',
      title: 'Sintel',
    ),
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _open(PlayerSource source) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VideoScreen(source: source)),
    );
  }

  void _openCustomUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final token = _tokenController.text.trim();
    _open(
      PlayerSource.network(
        url,
        headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
        title: 'Custom stream',
        isLive: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── App bar ───────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 120,
            backgroundColor: const Color(0xFF0A0A0A),
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'mk_player testbed',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
            ),
          ),

          // ── Custom URL card ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _CustomUrlCard(
                urlController: _urlController,
                tokenController: _tokenController,
                onPlay: _openCustomUrl,
                accentColor: theme.colorScheme.primary,
              ),
            ),
          ),

          // ── Section label ─────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'TEST SOURCES',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),

          // ── Preset list ───────────────────────────────────────────────────
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _PresetTile(
                preset: _presets[i],
                onTap: () => _open(_presets[i].source),
              ),
              childCount: _presets.length,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom URL input card
// ─────────────────────────────────────────────────────────────────────────────

class _CustomUrlCard extends StatelessWidget {
  final TextEditingController urlController;
  final TextEditingController tokenController;
  final VoidCallback onPlay;
  final Color accentColor;

  const _CustomUrlCard({
    required this.urlController,
    required this.tokenController,
    required this.onPlay,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Custom URL',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.white70,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          _Field(
            controller: urlController,
            hint: 'https://example.com/stream.m3u8',
            label: 'Stream URL',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 8),
          _Field(
            controller: tokenController,
            hint: 'Optional Bearer token',
            label: 'Auth token',
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Play'),
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String label;
  final TextInputType? keyboardType;

  const _Field({
    required this.controller,
    required this.hint,
    required this.label,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13, color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        labelText: label,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withAlpha(13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preset tile
// ─────────────────────────────────────────────────────────────────────────────

class _PresetTile extends StatelessWidget {
  final _Preset preset;
  final VoidCallback onTap;

  const _PresetTile({required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(preset.icon, color: Colors.white54, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preset.subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white24,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
