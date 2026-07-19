// Throwaway entrypoint to reproduce DASH playback failure. Safe to delete.
import 'package:flutter/material.dart';
import 'package:mk_player/mk_player.dart';

import 'screens/video_screen.dart';

const _dashUrl =
    'https://nv-staging.b-cdn.net/bcdn_token=HS256-3gZdi6rI0R_uFr3FGzT7ymJJsWfaBBxeC8oVpHFNJpQ&token_path=%2F01KXCB7V3VZXJR08QVR4F72986%2F&expires=1784497096/01KXCB7V3VZXJR08QVR4F72986/01KXCBB3ADXV8KYC328S4XYFWJ.mpd';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: VideoScreen(
        source: PlayerSource.network(
          _dashUrl,
          title: 'DASH repro',
          format: PlayerVideoFormat.dash,
        ),
      ),
    ),
  );
}
