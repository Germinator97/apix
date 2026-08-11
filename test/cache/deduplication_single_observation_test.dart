import 'dart:convert';

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// One logical request must produce one of everything, whether or not
/// deduplication is installed.
///
/// a consumer hit this with a `CancelToken` on a search field: one cancelled
/// request per keystroke, each producing two Sentry events.
///
/// The mechanism took three attempts to pin down, so it is worth recording
/// what it is *not*. It is not the inner request being observed alongside the
/// outer one — on a cancellation the inner request never reaches the error
/// chain. It is not `handler.reject` replaying the outcome either, which is why
/// marking the request inside the deduplicator's `catch` changed nothing.
///
/// What happens: outer and inner share a `CancelToken`, so a cancellation
/// rejects them independently and the *outer* request enters the error chain
/// twice. Hence the fix claims the request at observation time rather than
/// trying to predict which pass to drop.
class _SlowAdapter implements HttpClientAdapter {
  int hits = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    hits++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'value': 'ok'})),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FailingAdapter implements HttpClientAdapter {
  int hits = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    hits++;
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'message': 'boom'})),
      500,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Tally {
  final logs = <LogEntry>[];
  final metrics = <RequestMetrics>[];
  final captured = <Object>[];

  int get errorLogs => logs.where((l) => l.error != null).length;

  ApiClient client({
    required HttpClientAdapter adapter,
    required bool dedup,
  }) {
    return ApiClientFactory.create(
      baseUrl: 'https://api.test',
      deduplicationConfig: dedup ? const DeduplicationConfig() : null,
      loggerConfig: LoggerConfig(level: LogLevel.info, logHandler: logs.add),
      metricsConfig: MetricsConfig(onMetrics: metrics.add),
      errorTrackingConfig: ErrorTrackingConfig(
        onError: (e, {stackTrace, extra, tags}) async => captured.add(e),
      ),
      httpClientAdapter: adapter,
    );
  }
}

Future<_Tally> _cancelDuring({required bool dedup}) async {
  final tally = _Tally();
  final adapter = _SlowAdapter();
  final client = tally.client(adapter: adapter, dedup: dedup);

  final token = CancelToken();
  final inFlight = client.get<dynamic>('/search', cancelToken: token);
  await Future<void>.delayed(const Duration(milliseconds: 10));
  token.cancel('replaced by the next keystroke');

  try {
    await inFlight;
  } on ApiException {
    // expected
  }
  await Future<void>.delayed(const Duration(milliseconds: 80));
  return tally;
}

void main() {
  group('a cancelled request is observed once', () {
    test('with deduplication, exactly as without it', () async {
      final without = await _cancelDuring(dedup: false);
      final with_ = await _cancelDuring(dedup: true);

      expect(
        with_.captured.length,
        equals(without.captured.length),
        reason: 'deduplication doubled Sentry events: '
            '${with_.captured.length} vs ${without.captured.length}',
      );
      expect(
        with_.errorLogs,
        equals(without.errorLogs),
        reason: 'deduplication doubled error logs: '
            '${with_.errorLogs} vs ${without.errorLogs}',
      );
    });

    test('and exactly once in absolute terms', () async {
      final tally = await _cancelDuring(dedup: true);

      expect(tally.captured, hasLength(1));
      expect(tally.errorLogs, equals(1));
    });
  });

  // The half that keeps the guard honest: skipping the second pass must not
  // skip the first. A marker set too early would silence observability
  // entirely, and every assertion above would still pass.
  group('a failing request is still observed', () {
    test('through the deduplicated path', () async {
      final tally = _Tally();
      final adapter = _FailingAdapter();
      final client = tally.client(adapter: adapter, dedup: true);

      try {
        await client.get<dynamic>('/x');
      } on ApiException {
        // expected
      }

      expect(adapter.hits, equals(1));
      expect(tally.captured, hasLength(1), reason: 'the tracker went quiet');
      expect(tally.errorLogs, equals(1), reason: 'the log sink went quiet');
      expect(tally.metrics, isNotEmpty, reason: 'metrics went quiet');
    });

    test('and a successful one is measured exactly once', () async {
      final tally = _Tally();
      final client = tally.client(adapter: _SlowAdapter(), dedup: true);

      await client.get<dynamic>('/x');

      expect(tally.metrics, hasLength(1));
      expect(tally.captured, isEmpty);
    });
  });
}
