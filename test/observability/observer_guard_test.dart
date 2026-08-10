import 'dart:async';
import 'dart:convert';

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collects errors that escaped to the zone instead of reaching a caller.
Future<List<Object>> escapedErrors(Future<void> Function() body) async {
  final escaped = <Object>[];
  final done = Completer<void>();

  runZonedGuarded(
    () async {
      try {
        await body();
      } finally {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (!done.isCompleted) done.complete();
      }
    },
    (error, stack) => escaped.add(error),
  );

  await done.future;
  return escaped;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.statusCode);

  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'value': 'ok'})),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Never _boom(Object? _) => throw StateError('observability backend is down');

void main() {
  // Every one of these failed before the guard, and each failure was measured
  // rather than assumed: a 200 came back as an ApiException, or an error
  // reached the zone with no one to receive it.
  //
  // The rule they all encode: a side channel must not decide whether the
  // request succeeded.
  group('a failing observer never breaks the request', () {
    test('logHandler that throws', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        loggerConfig:
            const LoggerConfig(level: LogLevel.info, logHandler: _boom),
        httpClientAdapter: _Adapter(200),
      );

      final escaped = await escapedErrors(() async {
        final response = await client.get<dynamic>('/x');
        expect(response.statusCode, equals(200));
      });

      expect(escaped, isEmpty);
    });

    test('onMetrics that throws', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        metricsConfig: const MetricsConfig(onMetrics: _boom),
        httpClientAdapter: _Adapter(200),
      );

      final escaped = await escapedErrors(() async {
        expect((await client.get<dynamic>('/x')).statusCode, equals(200));
      });

      expect(escaped, isEmpty);
    });

    test('onBreadcrumb that throws', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        errorTrackingConfig: ErrorTrackingConfig(
          onError: (e, {stackTrace, extra, tags}) async {},
          onBreadcrumb: _boom,
        ),
        httpClientAdapter: _Adapter(200),
      );

      final escaped = await escapedErrors(() async {
        expect((await client.get<dynamic>('/x')).statusCode, equals(200));
      });

      expect(escaped, isEmpty);
    });

    test('startSpan that throws', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        tracingConfig: TracingConfig(startSpan: (_, __) => _boom(null)),
        httpClientAdapter: _Adapter(200),
      );

      final escaped = await escapedErrors(() async {
        expect((await client.get<dynamic>('/x')).statusCode, equals(200));
      });

      expect(escaped, isEmpty);
    });

    // The subtle one, and the same shape as the deduplicator's: a Future
    // returned and dropped does not merely get ignored — when it rejects with
    // no listener, Dart reports it to the zone. From inside the component whose
    // whole job is receiving errors.
    test('onError that fails asynchronously', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        errorTrackingConfig: ErrorTrackingConfig(
          onError: (e, {stackTrace, extra, tags}) async =>
              throw StateError('tracker is down'),
        ),
        httpClientAdapter: _Adapter(500),
      );

      final escaped = await escapedErrors(() async {
        await expectLater(
          client.get<dynamic>('/x'),
          throwsA(isA<ServerException>()),
        );
      });

      expect(
        escaped,
        isEmpty,
        reason: 'the caller already got the 500; a tracker failing on top of '
            'it must not add an error nobody can handle',
      );
    });

    test('onError that throws synchronously', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        errorTrackingConfig: ErrorTrackingConfig(
          onError: (e, {stackTrace, extra, tags}) => throw StateError('down'),
        ),
        httpClientAdapter: _Adapter(500),
      );

      final escaped = await escapedErrors(() async {
        await expectLater(
          client.get<dynamic>('/x'),
          throwsA(isA<ServerException>()),
        );
      });

      expect(escaped, isEmpty);
    });
  });

  // The other half, and the one that matters most: silencing failures must not
  // silence success. A guard that swallowed everything would pass every test
  // above while quietly switching observability off.
  group('a healthy observer still receives everything', () {
    test('logs, metrics, breadcrumbs, spans and captures all arrive', () async {
      final logs = <LogEntry>[];
      final metrics = <RequestMetrics>[];
      final breadcrumbs = <Map<String, dynamic>>[];
      final captured = <Object>[];
      final spans = <String>[];

      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        loggerConfig: LoggerConfig(level: LogLevel.info, logHandler: logs.add),
        metricsConfig: MetricsConfig(onMetrics: metrics.add),
        errorTrackingConfig: ErrorTrackingConfig(
          onError: (e, {stackTrace, extra, tags}) async => captured.add(e),
          onBreadcrumb: (data) => breadcrumbs.add(data),
        ),
        tracingConfig: TracingConfig(
          startSpan: (op, description) {
            spans.add(description);
            return null;
          },
        ),
        httpClientAdapter: _Adapter(500),
      );

      try {
        await client.get<dynamic>('/x');
      } on ApiException {
        // expected
      }

      expect(logs, isNotEmpty, reason: 'the log sink went quiet');
      expect(metrics, isNotEmpty, reason: 'metrics went quiet');
      expect(breadcrumbs, isNotEmpty, reason: 'breadcrumbs went quiet');
      expect(captured, isNotEmpty, reason: 'the tracker went quiet');
      expect(spans, isNotEmpty, reason: 'tracing went quiet');
    });
  });
}
