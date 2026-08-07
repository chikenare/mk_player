import 'dart:async';

/// Device class reported to the telemetry API — the full set the endpoint
/// accepts.
enum TelemetryDeviceType {
  /// Browser.
  web,

  /// Phone / tablet.
  android,

  /// Android TV (or any other 10-foot device).
  tv,

  /// Anything else (desktop, iOS, …).
  other;

  String get wireName => name;
}

/// Payload `kind`. `playback` for the player, `download` for the downloader.
enum TelemetryKind {
  playback,
  download;

  String get wireName => name;
}

/// Configuration for playback telemetry reporting.
///
/// Pass it to [PlayerConfig.telemetry] and the player takes care of the whole
/// cycle: `start` on the first frame, `progress` every 30 seconds of actual
/// playback, `end` when the source stops or changes, and `error` on a fatal
/// player failure. Events are written to a persistent on-disk queue the moment
/// they happen and flushed in batches to `POST {apiUrl}` with
/// `Authorization: Bearer {authToken}`.
///
/// ```dart
/// PlayerConfig(
///   telemetry: TelemetryConfig(
///     apiUrl: 'https://api.example.com/api/telemetry',
///     authToken: sanctumToken,
///     appVersion: '3.4.1',
///     deviceType: TelemetryDeviceType.android,
///   ),
/// )
/// ```
///
/// Telemetry is only emitted for sources that carry a
/// [PlayerSource.contentId] — anything else is played without reporting.
class TelemetryConfig {
  /// Full endpoint URL the batches are posted to, e.g.
  /// `https://api.example.com/api/telemetry`.
  final String apiUrl;

  /// Token sent on every request as `Authorization: Bearer <token>`.
  ///
  /// A value that already starts with a scheme (`Bearer …`) is sent verbatim,
  /// so a host that stores the whole header value works too.
  ///
  /// Ignored when [tokenProvider] is set. On 401 the queue is kept intact and
  /// flushed after the next successful login (see [updateToken]).
  final String? authToken;

  /// Resolves the token per request — use this instead of [authToken] when it
  /// can be refreshed while the player is alive. Same header, same rules.
  final FutureOr<String?> Function()? tokenProvider;

  /// Version string of the host app, e.g. `'3.4.1'`. Truncated to the 32
  /// characters the API accepts.
  final String appVersion;

  /// `android` on a phone, `tv` on Android TV.
  final TelemetryDeviceType deviceType;

  /// Payload `kind`. `playback` for the player; `download` is reserved for the
  /// download manager.
  final TelemetryKind kind;

  /// How often a `progress` event is emitted while playing. Defaults to 30s,
  /// which is what the API expects.
  final Duration progressInterval;

  /// How often the queue is drained. Defaults to 60s; a flush is also
  /// triggered when a session ends and when a new source is opened.
  final Duration flushInterval;

  /// Maximum events per request. The API rejects more than 50, so a larger
  /// backlog is sent as several requests.
  final int maxBatchSize;

  /// Hard cap on the persistent queue. When exceeded the oldest events are
  /// dropped, so a device that has been offline for weeks cannot grow the
  /// file without bound.
  final int maxQueuedEvents;

  /// Base delay for the retry backoff after a network error or a 429 without
  /// `Retry-After`. Doubles per consecutive failure, capped at 15 minutes.
  final Duration retryBaseDelay;

  /// Absolute path of the queue file. Defaults to
  /// `<app-support>/mk_player/telemetry_queue.jsonl`.
  final String? queueFilePath;

  /// Cumulative bytes loaded from the network by the player, in bytes.
  ///
  /// The Flutter layer of ExoPlayer/Media3 does not surface `AnalyticsListener`
  /// counters, so mk_player cannot measure real network traffic on its own.
  /// Supply this hook (from a native `onBandwidthEstimate` /
  /// `onLoadCompleted` bridge) and the reporter turns the running total into
  /// per-event deltas. While it is `null`, `bytesDownloadedDelta` is **omitted**
  /// from the payload rather than estimated from the bitrate.
  final FutureOr<int?> Function()? bytesLoadedProvider;

  /// Set to `false` to compile the player with telemetry wired but silent.
  final bool enabled;

  /// Log queue/flush activity with `debugPrint`.
  final bool verbose;

  const TelemetryConfig({
    required this.apiUrl,
    required this.appVersion,
    this.authToken,
    this.tokenProvider,
    this.deviceType = TelemetryDeviceType.android,
    this.kind = TelemetryKind.playback,
    this.progressInterval = const Duration(seconds: 30),
    this.flushInterval = const Duration(seconds: 60),
    this.maxBatchSize = 50,
    this.maxQueuedEvents = 500,
    this.retryBaseDelay = const Duration(seconds: 5),
    this.queueFilePath,
    this.bytesLoadedProvider,
    this.enabled = true,
    this.verbose = false,
  })  : assert(maxBatchSize > 0 && maxBatchSize <= 50,
            'The API accepts between 1 and 50 events per request.'),
        assert(maxQueuedEvents > 0);

  /// [appVersion] cut to the length the API accepts.
  String get wireAppVersion =>
      appVersion.length <= 32 ? appVersion : appVersion.substring(0, 32);

  /// [apiUrl] parsed.
  Uri get endpoint => Uri.parse(apiUrl);

  /// Resolves the bearer token for the next request.
  Future<String?> resolveToken() async {
    final provider = tokenProvider;
    if (provider != null) return await provider();
    return authToken;
  }

  /// Returns a copy with a new token — the usual way to hand the player a
  /// freshly issued token after a re-login so the queue held back by a 401 can
  /// drain (see [CustomPlayerController.updateTelemetryToken]).
  TelemetryConfig updateToken(String? token) => copyWith(authToken: token);

  TelemetryConfig copyWith({
    String? apiUrl,
    String? authToken,
    FutureOr<String?> Function()? tokenProvider,
    String? appVersion,
    TelemetryDeviceType? deviceType,
    TelemetryKind? kind,
    Duration? progressInterval,
    Duration? flushInterval,
    int? maxBatchSize,
    int? maxQueuedEvents,
    Duration? retryBaseDelay,
    String? queueFilePath,
    FutureOr<int?> Function()? bytesLoadedProvider,
    bool? enabled,
    bool? verbose,
  }) {
    return TelemetryConfig(
      apiUrl: apiUrl ?? this.apiUrl,
      authToken: authToken ?? this.authToken,
      tokenProvider: tokenProvider ?? this.tokenProvider,
      appVersion: appVersion ?? this.appVersion,
      deviceType: deviceType ?? this.deviceType,
      kind: kind ?? this.kind,
      progressInterval: progressInterval ?? this.progressInterval,
      flushInterval: flushInterval ?? this.flushInterval,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
      maxQueuedEvents: maxQueuedEvents ?? this.maxQueuedEvents,
      retryBaseDelay: retryBaseDelay ?? this.retryBaseDelay,
      queueFilePath: queueFilePath ?? this.queueFilePath,
      bytesLoadedProvider: bytesLoadedProvider ?? this.bytesLoadedProvider,
      enabled: enabled ?? this.enabled,
      verbose: verbose ?? this.verbose,
    );
  }
}
