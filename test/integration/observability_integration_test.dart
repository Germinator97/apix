import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Observability Integration Tests', () {
    group('LoggerConfig', () {
      test('default values are sensible', () {
        const config = LoggerConfig();

        expect(config.level, LogLevel.info);
        expect(config.redactedHeaders, contains('Authorization'));
      });

      test('custom log level is respected', () {
        const config = LoggerConfig(level: LogLevel.trace);
        expect(config.level, LogLevel.trace);
      });

      test('custom log handler can be set', () {
        final entries = <LogEntry>[];
        final config = LoggerConfig(
          logHandler: (entry) => entries.add(entry),
        );

        expect(config.logHandler, isNotNull);
      });

      test('redacted headers can be customized', () {
        const config = LoggerConfig(
          redactedHeaders: ['X-Custom-Secret', 'Api-Key'],
        );

        expect(config.redactedHeaders, contains('X-Custom-Secret'));
        expect(config.redactedHeaders, contains('Api-Key'));
      });
    });

    group('LogLevel', () {
      test('all levels have prefixes', () {
        expect(LogLevel.error.prefix, contains('ERROR'));
        expect(LogLevel.warn.prefix, contains('WARN'));
        expect(LogLevel.info.prefix, contains('INFO'));
        expect(LogLevel.trace.prefix, contains('TRACE'));
      });

      test('none level has empty prefix', () {
        expect(LogLevel.none.prefix, isEmpty);
      });
    });

    group('LogEntry', () {
      test('creates with required fields', () {
        final entry = LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.info,
          message: 'Test message',
        );

        expect(entry.message, 'Test message');
        expect(entry.level, LogLevel.info);
      });

      test('creates with HTTP details', () {
        final entry = LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.info,
          message: 'Request',
          method: 'GET',
          url: 'https://api.example.com/users',
          statusCode: 200,
          durationMs: 150,
        );

        expect(entry.method, 'GET');
        expect(entry.url, contains('/users'));
        expect(entry.statusCode, 200);
        expect(entry.durationMs, 150);
      });
    });

    group('MetricsConfig', () {
      test('can set metrics callback', () {
        final metrics = <RequestMetrics>[];
        final config = MetricsConfig(
          onMetrics: (m) => metrics.add(m),
        );

        expect(config.onMetrics, isNotNull);
      });
    });

    group('RequestMetrics', () {
      test('creates with all required fields', () {
        final now = DateTime.now();
        final metrics = RequestMetrics(
          requestId: 'req-123',
          method: 'POST',
          url: 'https://api.example.com/users',
          path: '/users',
          startTime: now,
          statusCode: 201,
          durationMs: 250,
          requestSize: 100,
          responseSize: 500,
          success: true,
        );

        expect(metrics.requestId, 'req-123');
        expect(metrics.method, 'POST');
        expect(metrics.url, contains('/users'));
        expect(metrics.path, '/users');
        expect(metrics.startTime, now);
        expect(metrics.statusCode, 201);
        expect(metrics.durationMs, 250);
        expect(metrics.success, true);
      });

      test('copyWith creates modified copy', () {
        final now = DateTime.now();
        final original = RequestMetrics(
          requestId: 'req-123',
          method: 'GET',
          url: 'https://api.example.com/test',
          path: '/test',
          startTime: now,
          success: true,
        );

        final modified = original.copyWith(
          statusCode: 500,
          success: false,
          error: 'Server error',
        );

        expect(modified.requestId, 'req-123');
        expect(modified.statusCode, 500);
        expect(modified.success, false);
        expect(modified.error, 'Server error');
      });
    });

    group('ErrorTrackingConfig', () {
      test('default capture status codes include 5xx', () {
        const config = ErrorTrackingConfig();
        expect(config.captureStatusCodes, contains(500));
        expect(config.captureStatusCodes, contains(502));
        expect(config.captureStatusCodes, contains(503));
      });

      test('can set custom onError callback', () {
        final exceptions = <Object>[];
        final config = ErrorTrackingConfig(
          onError: (Object e,
              {StackTrace? stackTrace,
              Map<String, dynamic>? extra,
              Map<String, String>? tags}) async {
            exceptions.add(e);
          },
        );

        expect(config.onError, isNotNull);
      });

      test('can set custom breadcrumb callback', () {
        final breadcrumbs = <Map<String, dynamic>>[];
        final config = ErrorTrackingConfig(
          onBreadcrumb: (Map<String, dynamic> data) => breadcrumbs.add(data),
        );

        expect(config.onBreadcrumb, isNotNull);
      });

      test('redacted headers include sensitive data', () {
        const config = ErrorTrackingConfig();
        expect(config.redactedHeaders, contains('Authorization'));
        expect(config.redactedHeaders, contains('Cookie'));
      });

      test('can customize capture status codes', () {
        const config = ErrorTrackingConfig(
          captureStatusCodes: {400, 401, 500},
        );

        expect(config.captureStatusCodes, contains(400));
        expect(config.captureStatusCodes, contains(401));
        expect(config.captureStatusCodes, contains(500));
        expect(config.captureStatusCodes.contains(502), false);
      });
    });

    group('SentrySetupOptions', () {
      test('creates with DSN and environment', () {
        const options = SentrySetupOptions(
          dsn: 'https://test@sentry.io/123',
          environment: 'test',
        );

        expect(options.dsn, 'https://test@sentry.io/123');
        expect(options.environment, 'test');
      });

      test('has sensible defaults', () {
        const options = SentrySetupOptions(
          dsn: 'https://test@sentry.io/123',
          environment: 'test',
        );

        expect(options.enabled, true);
        expect(options.filterNetworkNoise, true);
      });

      test('development factory sets correct defaults', () {
        final options = SentrySetupOptions.development(
          dsn: 'https://test@sentry.io/123',
        );

        expect(options.environment, 'development');
      });

      test('production factory sets correct defaults', () {
        final options = SentrySetupOptions.production(
          dsn: 'https://test@sentry.io/123',
        );

        expect(options.environment, 'production');
      });
    });
  });
}
