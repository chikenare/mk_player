import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mk_player/src/playback/playback_event.dart';
import 'package:mk_player/src/playback/playback_session_tracker.dart';
import 'package:mk_player/src/telemetry/telemetry_client.dart';
import 'package:mk_player/src/telemetry/telemetry_config.dart';
import 'package:mk_player/src/telemetry/telemetry_queue.dart';
import 'package:mk_player/src/telemetry/telemetry_reporter.dart';
import 'package:mk_player/src/telemetry/telemetry_serializer.dart';

/// Captures the batches a reporter tries to deliver and lets a test decide how
/// the API answers.
class _FakeClient extends TelemetryClient {
  _FakeClient(super.config, {this.result = const TelemetryUploadResult(
    TelemetryUploadStatus.accepted,
  )});

  TelemetryUploadResult result;
  final List<List<PlaybackEvent>> batches = [];

  List<PlaybackEvent> get sent => [for (final b in batches) ...b];

  @override
  Future<TelemetryUploadResult> send(List<PlaybackEvent> events) async {
    batches.add(List.of(events));
    return result;
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('mk_telemetry'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  TelemetryConfig configFor({
    Duration progressInterval = const Duration(milliseconds: 60),
    int maxBatchSize = 50,
    int maxQueuedEvents = 500,
    Future<int?> Function()? bytesLoadedProvider,
  }) =>
      TelemetryConfig(
        apiUrl: 'https://api.example.com/api/telemetry',
        appVersion: '3.4.1',
        authToken: 'token',
        progressInterval: progressInterval,
        flushInterval: const Duration(seconds: 30),
        maxBatchSize: maxBatchSize,
        maxQueuedEvents: maxQueuedEvents,
        bytesLoadedProvider: bytesLoadedProvider,
        queueFilePath: '${tempDir.path}/queue.jsonl',
      );

  group('Telemetry wire format', () {
    test('occurredAt always carries an offset', () {
      final local = PlaybackEvent(
        type: PlaybackEventType.start,
        sessionId: '01J4X8Y3NDQ2M9V7B1KQZT5W6E',
        occurredAt: DateTime(2026, 8, 6, 22, 30, 30),
        contentId: 812,
        positionSeconds: 0,
      );
      final stamp =
          TelemetryEventSerializer.toJson(local)['occurredAt'] as String;
      expect(stamp, matches(r'(Z|[+-]\d{2}:\d{2})$'));

      final utc = PlaybackEvent(
        type: PlaybackEventType.start,
        sessionId: '01J4X8Y3NDQ2M9V7B1KQZT5W6E',
        occurredAt: DateTime.utc(2026, 8, 6, 22, 30, 30),
        contentId: 812,
        positionSeconds: 0,
      );
      expect(TelemetryEventSerializer.toJson(utc)['occurredAt'],
          endsWith('Z'));
    });

    test('never serialises a numeric field as null and clamps to the server '
        'ranges', () {
      final event = PlaybackEvent(
        type: PlaybackEventType.progress,
        sessionId: '01J4X8Y3NDQ2M9V7B1KQZT5W6E',
        occurredAt: _fixedTime,
        contentId: 812,
        episodeId: null, // a movie
        positionSeconds: 999999,
        secondsWatchedDelta: 4000,
        bytesDownloadedDelta: 9000000000,
        stallCountDelta: -3,
        stalledSecondsDelta: 900,
        startupMs: 900000,
        resolution: '1080-with-a-very-long-label',
      );
      final json = TelemetryEventSerializer.toJson(event);

      // An explicit null in a numeric field is a 422; an absent key is 0.
      expect(json.values.any((v) => v == null), isFalse);
      expect(json.containsKey('episodeId'), isFalse);
      expect(json['positionSeconds'], 360000);
      expect(json['secondsWatchedDelta'], 300);
      expect(json['bytesDownloadedDelta'], 5000000000);
      expect(json['stallCountDelta'], 0);
      expect(json['stalledSecondsDelta'], 300);
      expect(json['startupMs'], 600000);
      expect((json['resolution'] as String).length, 16);
    });

    test('rejects queued events the API would refuse', () {
      final valid = TelemetryEventSerializer.toJson(PlaybackEvent(
        type: PlaybackEventType.progress,
        sessionId: '01J4X8Y3NDQ2M9V7B1KQZT5W6E',
        occurredAt: _fixedTime,
        contentId: 812,
        positionSeconds: 10,
      ));

      expect(TelemetryEventSerializer.fromJson(valid), isNotNull);
      expect(TelemetryEventSerializer.fromJson({...valid}..remove('sessionId')),
          isNull);
      expect(TelemetryEventSerializer.fromJson({...valid, 'sessionId': 'short'}),
          isNull);
      expect(
          TelemetryEventSerializer.fromJson({...valid, 'contentId': 0}), isNull);
    });

    test('omits bytesDownloadedDelta when it cannot be measured', () {
      final json = TelemetryEventSerializer.toJson(PlaybackEvent(
        type: PlaybackEventType.progress,
        sessionId: '01J4X8Y3NDQ2M9V7B1KQZT5W6E',
        occurredAt: _fixedTime,
        contentId: 812,
        positionSeconds: 10,
      ));
      expect(json.containsKey('bytesDownloadedDelta'), isFalse);
    });

    test('survives a JSON round-trip', () {
      final event = PlaybackEvent(
        type: PlaybackEventType.progress,
        sessionId: '01J4X8Y3NDQ2M9V7B1KQZT5W6E',
        occurredAt: DateTime.now(),
        contentId: 812,
        episodeId: 4711,
        positionSeconds: 1284,
        secondsWatchedDelta: 30,
        bytesDownloadedDelta: 10485760,
        stallCountDelta: 1,
        stalledSecondsDelta: 4,
        resolution: '1080',
      );
      final restored =
          TelemetryEventSerializer.fromJson(TelemetryEventSerializer.toJson(event))!;
      expect(TelemetryEventSerializer.toJson(restored),
          TelemetryEventSerializer.toJson(event));
    });
  });

  group('TelemetryQueue', () {
    test('persists across instances and drops the oldest on overflow',
        () async {
      final path = '${tempDir.path}/queue.jsonl';
      final queue = TelemetryQueue(maxEvents: 3, filePath: path);
      for (var i = 0; i < 5; i++) {
        await queue.add(PlaybackEvent(
          type: PlaybackEventType.progress,
          sessionId: 'SESSION_${i}X',
          occurredAt: DateTime.now(),
          contentId: 1,
          positionSeconds: i,
        ));
      }

      final reopened = TelemetryQueue(maxEvents: 3, filePath: path);
      expect(await reopened.length, 3);
      final head = await reopened.peek(3);
      expect(head.first.positionSeconds, 2); // 0 and 1 were dropped

      await reopened.removeFirst(2);
      expect(await TelemetryQueue(maxEvents: 3, filePath: path).length, 1);
    });
  });

  group('TelemetryReporter', () {
    test('emits start with startupMs and zeroed deltas', () async {
      final config = configFor();
      final client = _FakeClient(config);
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812, episodeId: 4711);
      reporter.onResolution(1080);
      reporter.onPlaying(Duration.zero);
      await reporter.close();

      final start = client.sent.first;
      expect(start.type, PlaybackEventType.start);
      expect(start.contentId, 812);
      expect(start.episodeId, 4711);
      expect(start.resolution, '1080');
      expect(start.startupMs, isNotNull);
      expect(start.secondsWatchedDelta, 0);
      expect(start.stallCountDelta, 0);
    });

    test('counts played position as watched time and ignores seeks', () async {
      final config = configFor(progressInterval: const Duration(days: 1));
      final client = _FakeClient(config);
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812);
      reporter.onPlaying(Duration.zero);
      // 10 seconds of playback in 1-second steps.
      for (var s = 1; s <= 10; s++) {
        reporter.onPosition(Duration(seconds: s), playing: true);
      }
      // A jump to 20:00 is a seek, and playback continues from there.
      reporter.onPosition(const Duration(minutes: 20), playing: true);
      for (var s = 1; s <= 4; s++) {
        reporter.onPosition(
          Duration(minutes: 20, seconds: s),
          playing: true,
        );
      }
      await reporter.close();

      final end = client.sent.last;
      expect(end.type, PlaybackEventType.end);
      expect(end.secondsWatchedDelta, 14); // 10 + 4, the seek excluded
      expect(end.positionSeconds, 20 * 60 + 4);
    });

    test('progress ticks only while playing, and deltas reset each event',
        () async {
      final config = configFor(progressInterval: const Duration(milliseconds: 40));
      final client = _FakeClient(config);
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812);
      reporter.onPlaying(Duration.zero);
      for (var s = 1; s <= 5; s++) {
        reporter.onPosition(Duration(seconds: s), playing: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));

      reporter.onPaused(const Duration(seconds: 5));
      final afterPause = client.sent.length;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(client.sent.length, afterPause,
          reason: 'no progress events while paused');

      await reporter.close();
      final progress =
          client.sent.where((e) => e.type == PlaybackEventType.progress);
      expect(progress, isNotEmpty);
      expect(progress.first.secondsWatchedDelta, 5);
      // The counter was reset, so the following events carry no watched time.
      expect(
        progress.skip(1).every((e) => e.secondsWatchedDelta == 0),
        isTrue,
      );
    });

    test('counts stalls only after playback started', () async {
      final config = configFor(progressInterval: const Duration(days: 1));
      final client = _FakeClient(config);
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812);
      reporter.onBufferingStart(); // startup buffering, not a stall
      reporter.onBufferingEnd();
      reporter.onPlaying(Duration.zero);
      reporter.onBufferingStart();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      reporter.onBufferingEnd();
      await reporter.close();

      expect(client.sent.first.stallCountDelta, 0); // start event
      expect(client.sent.last.stallCountDelta, 1);
    });

    test('turns the cumulative byte counter into deltas', () async {
      var total = 1000;
      final config = configFor(
        progressInterval: const Duration(days: 1),
        bytesLoadedProvider: () async => total,
      );
      final client = _FakeClient(config);
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812);
      await Future<void>.delayed(Duration.zero); // baseline read
      reporter.onPlaying(Duration.zero);
      total = 1000 + 10485760;
      await reporter.close();

      expect(client.sent.last.bytesDownloadedDelta, 10485760);
    });

    test('repeats one session id across its events and a new one per load',
        () async {
      final config = configFor(progressInterval: const Duration(days: 1));
      final client = _FakeClient(config);
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812);
      final first = reporter.sessionId;
      reporter.onPlaying(Duration.zero);
      reporter.beginSession(contentId: 812); // played again
      final second = reporter.sessionId;
      reporter.onPlaying(Duration.zero);
      await reporter.close();

      expect(first, matches(sessionIdPattern));
      expect(second, matches(sessionIdPattern));
      expect(second, isNot(first));
      // start + end for each session, each carrying its own id.
      expect(client.sent.map((e) => e.sessionId).toList(),
          [first, first, second, second]);
    });

    test('a rebuffer spanning several progress events counts as one stall',
        () async {
      final config =
          configFor(progressInterval: const Duration(milliseconds: 30));
      final client = _FakeClient(config);
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812);
      reporter.onPlaying(Duration.zero);
      reporter.onBufferingStart();
      // Frozen across several progress ticks.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      reporter.onBufferingEnd();
      await reporter.close();

      final stalls = client.sent.fold<int>(0, (sum, e) => sum + e.stallCountDelta);
      expect(stalls, 1, reason: 'one freeze is one stall, however long');
      final stalled =
          client.sent.fold<int>(0, (sum, e) => sum + e.stalledSecondsDelta);
      expect(stalled, greaterThanOrEqualTo(0));
    });

    test('a failure before the first frame opens no session and reports nothing',
        () async {
      final config = configFor(progressInterval: const Duration(days: 1));
      final client = _FakeClient(config);
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812);
      reporter.reportError(); // never reached the first frame
      await reporter.close();

      expect(client.sent, isEmpty);
    });

    test('refuses a contentId the API would reject', () async {
      final config = configFor(progressInterval: const Duration(days: 1));
      final client = _FakeClient(config);
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 0);
      expect(reporter.sessionActive, isFalse);
      reporter.onPlaying(Duration.zero);
      await reporter.close();

      expect(client.sent, isEmpty);
    });

    test('replaying the same media closes the previous session first',
        () async {
      final config = configFor(progressInterval: const Duration(days: 1));
      final client = _FakeClient(config);
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812);
      reporter.onPlaying(Duration.zero);

      reporter.beginSession(contentId: 812); // same media, played again
      reporter.onPlaying(Duration.zero);
      await reporter.close();

      expect(
        client.sent.map((e) => e.type).toList(),
        [
          PlaybackEventType.start,
          PlaybackEventType.end,
          PlaybackEventType.start,
          PlaybackEventType.end,
        ],
      );
    });

    test('keeps events queued on 401 and delivers them after a new token',
        () async {
      final config = configFor(progressInterval: const Duration(days: 1));
      final client = _FakeClient(config,
          result: const TelemetryUploadResult(
              TelemetryUploadStatus.unauthorized));
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812);
      reporter.onPlaying(Duration.zero);
      reporter.endSession();
      await reporter.flush(ignoreBackoff: true);
      expect(await reporter.queuedEventCount, 2);

      client.result =
          const TelemetryUploadResult(TelemetryUploadStatus.accepted);
      reporter.updateToken('fresh-token');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await reporter.queuedEventCount, 0);

      await reporter.close();
    });

    test('drops permanently rejected batches (422)', () async {
      final config = configFor(progressInterval: const Duration(days: 1));
      final client = _FakeClient(config,
          result: const TelemetryUploadResult(TelemetryUploadStatus.invalid));
      final reporter = TelemetryReporter(config, client: client);

      reporter.beginSession(contentId: 812);
      reporter.onPlaying(Duration.zero);
      reporter.endSession();
      await reporter.flush(ignoreBackoff: true);

      expect(await reporter.queuedEventCount, 0);
      await reporter.close();
    });

    test('splits a backlog over 50 events into several requests', () async {
      final config = configFor(progressInterval: const Duration(days: 1));
      final client = _FakeClient(config,
          result: const TelemetryUploadResult(
              TelemetryUploadStatus.transient));
      final reporter = TelemetryReporter(config, client: client);

      // Fill the queue behind a failing endpoint: 60 sessions, 2 events each.
      for (var i = 0; i < 60; i++) {
        reporter.beginSession(contentId: 812);
        reporter.onPlaying(Duration.zero);
      }
      reporter.endSession();
      await reporter.flush(ignoreBackoff: true);
      expect(await reporter.queuedEventCount, greaterThan(50));

      client.batches.clear();
      client.result =
          const TelemetryUploadResult(TelemetryUploadStatus.accepted);
      await reporter.flush(ignoreBackoff: true);

      expect(client.batches.length, greaterThan(1));
      expect(client.batches.every((b) => b.length <= 50), isTrue);
      expect(await reporter.queuedEventCount, 0);
      await reporter.close();
    });
  });

  group('Playback event sinks', () {
    /// Wires a tracker the way [CustomPlayerController] does: one tracker, the
    /// host callback as a sink, the reporter attached to that same tracker.
    ({
      PlaybackSessionTracker tracker,
      TelemetryReporter reporter,
      _FakeClient client,
      List<PlaybackEvent> seen,
    }) wireBoth({
      TelemetryConfig? config,
      TelemetryUploadResult result =
          const TelemetryUploadResult(TelemetryUploadStatus.accepted),
      PlaybackEventSink? extraSink,
    }) {
      final effective = config ?? configFor(progressInterval: const Duration(days: 1));
      final client = _FakeClient(effective, result: result);
      final seen = <PlaybackEvent>[];
      final tracker =
          PlaybackSessionTracker(options: effective.playbackOptions);
      if (extraSink != null) tracker.addSink(extraSink);
      tracker.addSink(seen.add);
      final reporter =
          TelemetryReporter.forTracker(effective, tracker, client: client);
      return (tracker: tracker, reporter: reporter, client: client, seen: seen);
    }

    test('the callback measures a session with no TelemetryConfig at all',
        () async {
      final seen = <PlaybackEvent>[];
      final tracker = PlaybackSessionTracker(
        options: const PlaybackSessionOptions(
          progressInterval: Duration(milliseconds: 40),
        ),
        sinks: [seen.add],
      );

      tracker.beginSession(contentId: 812, episodeId: 4711);
      tracker.onResolution(1080);
      tracker.onPlaying(Duration.zero);
      for (var second = 1; second <= 3; second++) {
        tracker.onPosition(Duration(seconds: second), playing: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      tracker.dispose();
      await tracker.settled;

      expect(seen.first.type, PlaybackEventType.start);
      expect(seen.first.startupMs, isNotNull);
      expect(seen.first.resolution, '1080');
      expect(seen.last.type, PlaybackEventType.end);
      expect(seen.where((e) => e.type == PlaybackEventType.progress), isNotEmpty);
      expect(seen.map((e) => e.episodeId).toSet(), {4711});
      expect(seen.fold<int>(0, (sum, e) => sum + e.secondsWatchedDelta), 3);
      // Measurement only: nothing was queued, nothing was sent.
      expect(seen.map((e) => e.sessionId).toSet().length, 1);
    });

    test('both sinks get the same event exactly once', () async {
      final w = wireBoth();

      w.tracker.beginSession(contentId: 812);
      w.tracker.onPlaying(Duration.zero);
      w.tracker.onPosition(const Duration(seconds: 1), playing: true);
      w.tracker.endSession();
      await w.reporter.close();
      w.tracker.dispose();

      expect(w.seen.map((e) => e.type).toList(),
          [PlaybackEventType.start, PlaybackEventType.end]);
      expect(w.client.sent.length, w.seen.length);
      for (var i = 0; i < w.seen.length; i++) {
        // The very same instance on both sides — measured once, reported twice.
        expect(identical(w.client.sent[i], w.seen[i]), isTrue);
      }
    });

    test('one start per media load when telemetry and callback run together',
        () async {
      final w = wireBoth();
      expect(identical(w.reporter.tracker, w.tracker), isTrue,
          reason: 'the reporter must not build a tracker of its own');

      w.tracker.beginSession(contentId: 812);
      w.tracker.onPlaying(Duration.zero);
      w.tracker.beginSession(contentId: 812); // played again
      w.tracker.onPlaying(Duration.zero);
      await w.reporter.close();
      w.tracker.dispose();

      final starts =
          w.seen.where((e) => e.type == PlaybackEventType.start).toList();
      expect(starts.length, 2, reason: 'one start per load, never a duplicate');
      expect(starts.map((e) => e.sessionId).toSet().length, 2);
      expect(w.client.sent.where((e) => e.type == PlaybackEventType.start).length,
          2);
      expect(w.client.sent.length, w.seen.length);
    });

    test('an exception from the callback leaves the queue untouched', () async {
      final w = wireBoth(
        result: const TelemetryUploadResult(TelemetryUploadStatus.unauthorized),
        extraSink: (_) => throw StateError('host app blew up'),
      );

      w.tracker.beginSession(contentId: 812);
      w.tracker.onPlaying(Duration.zero);
      w.tracker.endSession();
      await w.reporter.flush(ignoreBackoff: true);

      // The throwing sink runs first, and neither the sink after it nor the
      // queue behind it notices.
      expect(w.seen.map((e) => e.type).toList(),
          [PlaybackEventType.start, PlaybackEventType.end]);
      expect(await w.reporter.queuedEventCount, 2);
      expect(w.tracker.sessionActive, isFalse);

      await w.reporter.close();
      w.tracker.dispose();
    });

    test('a source without contentId produces no events on either side',
        () async {
      final w = wireBoth(
          config: configFor(progressInterval: const Duration(milliseconds: 30)));

      // No session is ever opened for it — the player still reports position,
      // buffering and resolution while it plays.
      w.tracker.onPlaying(Duration.zero);
      w.tracker.onPosition(const Duration(seconds: 1), playing: true);
      w.tracker.onBufferingStart();
      w.tracker.onBufferingEnd();
      w.tracker.onResolution(1080);
      w.tracker.endSession();
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await w.reporter.close();
      w.tracker.dispose();

      expect(w.seen, isEmpty);
      expect(w.client.sent, isEmpty);
      expect(await w.reporter.queuedEventCount, 0);
    });

    test('the former TelemetryEvent names still resolve', () {
      const TelemetryEventType type = PlaybackEventType.start;
      final TelemetryEvent event = PlaybackEvent(
        type: type,
        sessionId: '01J4X8Y3NDQ2M9V7B1KQZT5W6E',
        occurredAt: _fixedTime,
        contentId: 812,
        positionSeconds: 0,
      );
      expect(event, isA<PlaybackEvent>());
      expect(TelemetryEventSerializer.toJson(event)['type'], 'start');
    });
  });
}

final _fixedTime = DateTime.utc(2026, 8, 6, 22, 30, 30);
