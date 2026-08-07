import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mk_player/mk_player.dart';
import 'package:mk_player/src/tv/remote_key.dart';
import 'package:mk_player/src/tv/tv_chrome.dart';
import 'package:mk_player/src/tv/tv_focusable.dart';
import 'package:mk_player/src/widgets/controls_overlay.dart';

void main() {
  group('mapRemoteKey', () {
    test('maps the D-pad', () {
      expect(mapRemoteKey(LogicalKeyboardKey.arrowLeft), RemoteKey.left);
      expect(mapRemoteKey(LogicalKeyboardKey.arrowRight), RemoteKey.right);
      expect(mapRemoteKey(LogicalKeyboardKey.arrowUp), RemoteKey.up);
      expect(mapRemoteKey(LogicalKeyboardKey.arrowDown), RemoteKey.down);
    });

    test('maps every flavour of "OK"', () {
      // DPAD_CENTER arrives as `select`, a keyboard as `enter`, a pad as A.
      for (final key in [
        LogicalKeyboardKey.select,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.numpadEnter,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.gameButtonA,
      ]) {
        expect(mapRemoteKey(key), RemoteKey.select, reason: '$key');
      }
    });

    test('maps the transport keys', () {
      expect(
          mapRemoteKey(LogicalKeyboardKey.mediaPlayPause), RemoteKey.playPause);
      expect(mapRemoteKey(LogicalKeyboardKey.mediaPlay), RemoteKey.play);
      expect(mapRemoteKey(LogicalKeyboardKey.mediaPause), RemoteKey.pause);
      expect(mapRemoteKey(LogicalKeyboardKey.mediaStop), RemoteKey.stop);
      expect(mapRemoteKey(LogicalKeyboardKey.mediaFastForward),
          RemoteKey.fastForward);
      expect(mapRemoteKey(LogicalKeyboardKey.mediaRewind), RemoteKey.rewind);
      expect(mapRemoteKey(LogicalKeyboardKey.mediaTrackNext), RemoteKey.next);
      expect(mapRemoteKey(LogicalKeyboardKey.mediaTrackPrevious),
          RemoteKey.previous);
    });

    test('maps back', () {
      expect(mapRemoteKey(LogicalKeyboardKey.escape), RemoteKey.back);
      expect(mapRemoteKey(LogicalKeyboardKey.goBack), RemoteKey.back);
      expect(mapRemoteKey(LogicalKeyboardKey.gameButtonB), RemoteKey.back);
    });

    test('leaves the system keys alone', () {
      for (final key in [
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.audioVolumeDown,
        LogicalKeyboardKey.audioVolumeMute,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.channelUp,
        LogicalKeyboardKey.keyA,
      ]) {
        expect(mapRemoteKey(key), isNull, reason: '$key');
      }
    });
  });

  group('resolveTvChrome', () {
    test('enabled/disabled ignore the input mode', () {
      for (final mode in FocusHighlightMode.values) {
        expect(resolveTvChrome(TvMode.enabled, mode), isTrue);
        expect(resolveTvChrome(TvMode.disabled, mode), isFalse);
      }
    });

    test('auto follows the input mode', () {
      expect(resolveTvChrome(TvMode.auto, FocusHighlightMode.touch), isFalse);
      expect(
          resolveTvChrome(TvMode.auto, FocusHighlightMode.traditional), isTrue);
    });
  });

  group('TvFocusable', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('the D-pad centre presses the focused control',
        (tester) async {
      var presses = 0;
      await tester.pumpWidget(wrap(TvFocusable(
        autofocus: true,
        onPressed: () => presses++,
        builder: (_, _) => const SizedBox(width: 40, height: 40),
      )));
      await tester.pump();

      // KEYCODE_DPAD_CENTER — the one Flutter's own default shortcuts miss.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(presses, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 2);
    });

    testWidgets('reports focus only once a key has been pressed',
        (tester) async {
      final states = <bool>[];
      await tester.pumpWidget(wrap(TvFocusable(
        autofocus: true,
        onPressed: () {},
        builder: (_, focused) {
          states.add(focused);
          return const SizedBox(width: 40, height: 40);
        },
      )));
      await tester.pump();
      // Touch is the initial highlight mode: focused, but no ring.
      expect(states.last, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(states.last, isTrue);
    });

    testWidgets('canRequestFocus: false keeps it tappable but unfocusable',
        (tester) async {
      var presses = 0;
      await tester.pumpWidget(wrap(TvFocusable(
        canRequestFocus: false,
        onPressed: () => presses++,
        builder: (_, focused) {
          expect(focused, isFalse);
          return const SizedBox(width: 40, height: 40);
        },
      )));
      await tester.pump();

      await tester.tap(find.byType(TvFocusable));
      expect(presses, 1);
      expect(
        tester.widget<Focus>(find.byType(Focus).first).canRequestFocus,
        isFalse,
      );
    });
  });

  group('PlayerControlsOverlay under a remote', () {
    // The controls are up exactly when back is intercepted, so PopScope.canPop
    // is a truthful (and stable) probe of the visibility state.
    final popScope = find.byWidgetPredicate((w) => w is PopScope);
    bool controlsVisible(WidgetTester tester) =>
        !((tester.widgetList(popScope).single as PopScope).canPop);

    Future<CustomPlayerController> pumpOverlay(
      WidgetTester tester, {
      PlayerConfig config = const PlayerConfig(tvMode: TvMode.enabled),
      VoidCallback? onToggleFullscreen,
    }) async {
      final controller = CustomPlayerController(config: config);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerControlsOverlay(
            controller: controller,
            config: config,
            onToggleFullscreen: onToggleFullscreen,
          ),
        ),
      ));
      await tester.pump();
      return controller;
    }

    // Lets the auto-hide, seek-commit and flash timers run out before the test
    // ends, and asserts nothing blew up on an uninitialised player.
    Future<void> drain(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 6));

    testWidgets('a D-pad press reveals the controls, back hides them',
        (tester) async {
      await pumpOverlay(tester);
      expect(controlsVisible(tester), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(controlsVisible(tester), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controlsVisible(tester), isFalse);

      await drain(tester);
    });

    testWidgets('arrows scrub, and repeats accumulate into one seek',
        (tester) async {
      await pumpOverlay(tester);

      // Both flash badges (◀ and ▶) carry the label; only the one on the side
      // being seeked is opaque, so the count is 2 either way.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controlsVisible(tester), isTrue);
      expect(find.text('10s'), findsNWidgets(2)); // seekSeconds default

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('20s'), findsNWidgets(2));
      expect(find.text('10s'), findsNothing);

      // …and back down again.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('10s'), findsNWidgets(2));

      await drain(tester);
    });

    testWidgets('transport keys are safe before the source is initialised',
        (tester) async {
      await pumpOverlay(tester);

      // Every one of these reaches better_player, which throws a StateError
      // until a data source exists — synchronously, in isPlaying()'s case.
      for (final key in [
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaPlay,
        LogicalKeyboardKey.mediaPause,
        LogicalKeyboardKey.mediaStop,
        LogicalKeyboardKey.select,
        LogicalKeyboardKey.mediaFastForward,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      await drain(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the skip keys call the host callbacks', (tester) async {
      var next = 0;
      var previous = 0;
      await pumpOverlay(
        tester,
        config: PlayerConfig(
          tvMode: TvMode.enabled,
          onSkipNext: () => next++,
          onSkipPrevious: () => previous++,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackPrevious);
      await tester.pump();

      expect(next, 1);
      expect(previous, 1);
      await drain(tester);
    });

    testWidgets('showAspectRatioButton overrides the per-platform default',
        (tester) async {
      // By tooltip, not by icon: the fit flash badge carries the same icon.
      final fitButton = find.byTooltip('Aspect ratio');

      // TV chrome on → shown by default (no pinch gesture to replace it).
      await pumpOverlay(tester);
      expect(fitButton, findsOneWidget);
      await drain(tester);

      await pumpOverlay(
        tester,
        config: const PlayerConfig(
          tvMode: TvMode.enabled,
          showAspectRatioButton: false,
        ),
      );
      expect(fitButton, findsNothing);
      await drain(tester);
    });

    testWidgets('showFullscreenButton overrides the per-skin default',
        (tester) async {
      final fullscreenButton = find.byTooltip('Fullscreen');

      // TV chrome on → dropped: the video already fills the screen.
      await pumpOverlay(tester, onToggleFullscreen: () {});
      expect(fullscreenButton, findsNothing);
      await drain(tester);

      await pumpOverlay(
        tester,
        config: const PlayerConfig(
          tvMode: TvMode.enabled,
          showFullscreenButton: true, // forced back on
        ),
        onToggleFullscreen: () {},
      );
      expect(fullscreenButton, findsOneWidget);
      await drain(tester);

      // See the note in the next test: the chrome is resolved once, in
      // initState, so the tree has to go before the skin changes.
      await tester.pumpWidget(const SizedBox.shrink());

      // Touch keeps it…
      await pumpOverlay(
        tester,
        config: const PlayerConfig(tvMode: TvMode.disabled),
        onToggleFullscreen: () {},
      );
      expect(fullscreenButton, findsOneWidget);
      await drain(tester);

      // …unless it is explicitly turned off.
      await pumpOverlay(
        tester,
        config: const PlayerConfig(
          tvMode: TvMode.disabled,
          showFullscreenButton: false,
        ),
        onToggleFullscreen: () {},
      );
      expect(fullscreenButton, findsNothing);
      await drain(tester);
    });

    testWidgets('the TV chrome drops the touch-only controls', (tester) async {
      // A host action keeps the subtitle entry alive without a real source, so
      // the track control is present in both skins and only its shape differs.
      final action = PlayerSheetAction(
        icon: Icons.search_rounded,
        label: 'Search online…',
        onTap: (_) {},
      );

      await pumpOverlay(
        tester,
        config: PlayerConfig(
          tvMode: TvMode.enabled,
          subtitleActions: [action],
        ),
      );

      // Speed, the ±10s buttons and the two separate track buttons are gone…
      expect(find.text('Speed'), findsNothing);
      expect(find.byIcon(Icons.replay_10_rounded), findsNothing);
      expect(find.byIcon(Icons.forward_10_rounded), findsNothing);
      expect(find.text('Subtitles'), findsNothing);
      // …replaced by one entry point, next to the play/pause indicator.
      expect(find.text('Audio & Subtitles'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await drain(tester);

      // Tear the tree down between skins: the overlay resolves the chrome once,
      // in initState, so pumping a new config over the same element would reuse
      // the TV state.
      await tester.pumpWidget(const SizedBox.shrink());

      // Touch keeps every one of them.
      await pumpOverlay(
        tester,
        config: PlayerConfig(
          tvMode: TvMode.disabled,
          subtitleActions: [action],
        ),
      );
      expect(find.text('Speed'), findsOneWidget);
      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
      expect(find.text('Subtitles'), findsOneWidget);
      expect(find.text('Audio & Subtitles'), findsNothing);
      await drain(tester);
    });

    testWidgets('the track panel opens on the right and closes on back',
        (tester) async {
      var searched = 0;
      await pumpOverlay(
        tester,
        config: PlayerConfig(
          tvMode: TvMode.enabled,
          subtitleActions: [
            PlayerSheetAction(
              icon: Icons.search_rounded,
              label: 'Search online…',
              onTap: (_) => searched++,
            ),
          ],
        ),
      );

      // Reveal the bar first: while it is faded out the controls ignore input.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      await tester.tap(find.text('Audio & Subtitles'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // One column per type, and no audio column with nothing to choose from.
      expect(find.text('SUBTITLES'), findsOneWidget);
      expect(find.text('AUDIO'), findsNothing);
      expect(find.text('Search online…'), findsOneWidget);

      // The panel carries its own Material: without one every label inherits
      // the framework's missing-Material style — yellow double underlines.
      expect(
        find.ancestor(
          of: find.text('SUBTITLES'),
          matching: find.byType(Material),
        ),
        findsWidgets,
      );
      final labelStyle =
          DefaultTextStyle.of(tester.element(find.text('SUBTITLES'))).style;
      expect(labelStyle.decoration ?? TextDecoration.none, TextDecoration.none);

      // Pinned to the right half of the screen, hugging its content.
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final panel = tester.getRect(find.text('SUBTITLES'));
      expect(panel.left, greaterThan(screen.width / 2));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SUBTITLES'), findsNothing);
      expect(searched, 0);

      await drain(tester);
    });

    testWidgets('TvMode.disabled ignores the remote entirely', (tester) async {
      await pumpOverlay(
        tester,
        config: const PlayerConfig(tvMode: TvMode.disabled),
      );

      expect(popScope, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('10s'), findsNothing);

      await drain(tester);
    });

    // The back arrow only exists on a route that can pop, which the plain
    // harness above is not.
    testWidgets('the back arrow is touch-only', (tester) async {
      final backArrow = find.byIcon(Icons.arrow_back_ios_new_rounded);

      Future<void> pumpPushed(PlayerConfig config) async {
        final controller = CustomPlayerController(config: config);
        addTearDown(controller.dispose);
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: SizedBox.expand()),
        ));
        unawaited(nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: PlayerControlsOverlay(
              controller: controller,
              config: config,
            ),
          ),
        )));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1)); // route transition
      }

      await pumpPushed(const PlayerConfig(tvMode: TvMode.disabled));
      expect(backArrow, findsOneWidget);
      await drain(tester);

      await pumpPushed(const PlayerConfig(tvMode: TvMode.enabled));
      expect(backArrow, findsNothing);
      await drain(tester);
    });
  });
}
