import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'telemetry_config.dart';
import 'telemetry_event.dart';

/// Outcome of a single `POST /api/telemetry` request.
enum TelemetryUploadStatus {
  /// 204 — the batch was stored; drop it from the queue.
  accepted,

  /// 422 — the payload will never be accepted; drop it and log.
  invalid,

  /// 401 — keep the queue and retry after the next login.
  unauthorized,

  /// 429 — keep the queue and back off, honouring `Retry-After`.
  rateLimited,

  /// Network failure, timeout or 5xx — keep the queue and retry with backoff.
  transient,

  /// No token available yet; nothing was sent.
  noToken,
}

class TelemetryUploadResult {
  final TelemetryUploadStatus status;

  /// Delay requested by the server (`Retry-After`), when present.
  final Duration? retryAfter;

  const TelemetryUploadResult(this.status, {this.retryAfter});

  bool get shouldDrop =>
      status == TelemetryUploadStatus.accepted ||
      status == TelemetryUploadStatus.invalid;
}

/// Thin HTTP client for the telemetry endpoint.
class TelemetryClient {
  TelemetryClient(this.config);

  final TelemetryConfig config;

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  bool _closed = false;

  String? _tokenOverride;
  bool _hasTokenOverride = false;

  /// Replaces the configured token, e.g. after a re-login.
  void updateToken(String? token) {
    _tokenOverride = token;
    _hasTokenOverride = true;
  }

  Future<String?> _token() async =>
      _hasTokenOverride ? _tokenOverride : await config.resolveToken();

  Future<TelemetryUploadResult> send(List<TelemetryEvent> events) async {
    if (_closed || events.isEmpty) {
      return const TelemetryUploadResult(TelemetryUploadStatus.accepted);
    }

    final token = await _token();
    if (token == null || token.isEmpty) {
      return const TelemetryUploadResult(TelemetryUploadStatus.noToken);
    }

    final payload = jsonEncode({
      'deviceType': config.deviceType.wireName,
      'kind': config.kind.wireName,
      'appVersion': config.wireAppVersion,
      'events': [for (final e in events) e.toJson()],
    });

    try {
      final request = await _http
          .postUrl(config.endpoint)
          .timeout(const Duration(seconds: 20));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      request.write(payload);

      final response = await request.close().timeout(
            const Duration(seconds: 30),
          );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10), onTimeout: () => '');

      switch (response.statusCode) {
        case 200:
        case 201:
        case 202:
        case 204:
          return const TelemetryUploadResult(TelemetryUploadStatus.accepted);
        case 401:
          return const TelemetryUploadResult(
              TelemetryUploadStatus.unauthorized);
        case 422:
          // Always logged, never gated behind `verbose`: a payload the API
          // will never accept is dropped from the queue, so without this line
          // a contract mismatch reads as "reporting fine, no data".
          // The response body currently comes back encrypted, so the status
          // and the batch size are what is actually diagnosable here.
          debugPrint('[MkPlayer] telemetry REJECTED (422) — dropping '
              '${events.length} event(s). First: ${events.first}. '
              'Body: $body');
          return const TelemetryUploadResult(TelemetryUploadStatus.invalid);
        case 429:
          return TelemetryUploadResult(
            TelemetryUploadStatus.rateLimited,
            retryAfter: _parseRetryAfter(
                response.headers.value(HttpHeaders.retryAfterHeader)),
          );
        default:
          // 4xx other than the ones above is a contract problem too — kept and
          // retried, but surfaced instead of silently backing off forever.
          if (response.statusCode < 500) {
            debugPrint('[MkPlayer] telemetry unexpected '
                '${response.statusCode} for ${events.length} event(s): $body');
          }
          return TelemetryUploadResult(
            TelemetryUploadStatus.transient,
            retryAfter: _parseRetryAfter(
                response.headers.value(HttpHeaders.retryAfterHeader)),
          );
      }
    } catch (e) {
      // Offline, DNS failure, TLS error, timeout — all retryable.
      if (config.verbose) {
        debugPrint('[MkPlayer] telemetry request failed: $e');
      }
      return const TelemetryUploadResult(TelemetryUploadStatus.transient);
    }
  }

  /// `Retry-After` is either delay-seconds or an HTTP date.
  static Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return Duration(seconds: seconds.clamp(0, 3600));
    try {
      final date = HttpDate.parse(value);
      final delta = date.difference(DateTime.now());
      return delta.isNegative ? Duration.zero : delta;
    } catch (_) {
      return null;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _http.close(force: true);
  }
}
