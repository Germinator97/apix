import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('LogLevel', () {
    test('has correct ordering', () {
      expect(LogLevel.none.index, equals(0));
      expect(LogLevel.error.index, equals(1));
      expect(LogLevel.warn.index, equals(2));
      expect(LogLevel.info.index, equals(3));
      expect(LogLevel.trace.index, equals(4));
    });
  });

  group('LogEntry', () {
    test('creates with required fields', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
        level: LogLevel.info,
        message: 'Test message',
      );

      expect(entry.level, equals(LogLevel.info));
      expect(entry.message, equals('Test message'));
    });

    test('toString formats correctly', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
        level: LogLevel.info,
        message: '→ Request',
        method: 'GET',
        url: 'https://api.com/users',
        statusCode: 200,
        durationMs: 150,
      );

      final str = entry.toString();
      expect(str, contains('INFO'));
      expect(str, contains('GET'));
      expect(str, contains('https://api.com/users'));
      expect(str, contains('200'));
      expect(str, contains('150ms'));
    });
  });

  group('LoggerConfig', () {
    test('creates with default values', () {
      final config = LoggerConfig();

      expect(config.enabled, isTrue);
      expect(config.level, equals(LogLevel.info));
      expect(config.logRequestHeaders, isTrue);
      expect(config.logRequestBody, isTrue);
      expect(config.logResponseHeaders, isFalse);
      expect(config.logResponseBody, isTrue);
      expect(config.logErrors, isTrue);
      expect(config.maxBodyLength, equals(1024));
    });

    test('trace factory creates verbose config', () {
      final config = LoggerConfig.trace();

      expect(config.level, equals(LogLevel.trace));
      expect(config.logResponseHeaders, isTrue);
      expect(config.includeTimestamp, isTrue);
    });

    test('minimal factory creates production config', () {
      final config = LoggerConfig.minimal();

      expect(config.level, equals(LogLevel.error));
      expect(config.logRequestHeaders, isFalse);
      expect(config.logRequestBody, isFalse);
    });

    test('disabled factory creates disabled config', () {
      final config = LoggerConfig.disabled();

      expect(config.enabled, isFalse);
    });

    test('shouldLog respects enabled flag', () {
      final disabled = LoggerConfig.disabled();
      final enabled = LoggerConfig();

      expect(disabled.shouldLog(LogLevel.info), isFalse);
      expect(enabled.shouldLog(LogLevel.info), isTrue);
    });

    test('shouldLog respects level', () {
      final config = LoggerConfig(level: LogLevel.warn);

      expect(config.shouldLog(LogLevel.error), isTrue);
      expect(config.shouldLog(LogLevel.warn), isTrue);
      expect(config.shouldLog(LogLevel.info), isFalse);
      expect(config.shouldLog(LogLevel.trace), isFalse);
    });

    test('shouldLog returns false for none level', () {
      final config = LoggerConfig(level: LogLevel.trace);

      expect(config.shouldLog(LogLevel.none), isFalse);
    });

    test('redactHeaders redacts sensitive headers', () {
      final config = LoggerConfig();
      final headers = <String, dynamic>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer secret-token',
        'Cookie': 'session=abc123',
        'X-Custom': 'value',
      };

      final redacted = config.redactHeaders(headers);

      expect(redacted['Content-Type'], equals('application/json'));
      expect(redacted['Authorization'], equals('[REDACTED]'));
      expect(redacted['Cookie'], equals('[REDACTED]'));
      expect(redacted['X-Custom'], equals('value'));
    });

    test('redactHeaders is case-insensitive', () {
      final config = LoggerConfig();
      final headers = <String, dynamic>{
        'authorization': 'Bearer token',
        'COOKIE': 'session=123',
      };

      final redacted = config.redactHeaders(headers);

      expect(redacted['authorization'], equals('[REDACTED]'));
      expect(redacted['COOKIE'], equals('[REDACTED]'));
    });

    test('truncateBody truncates long bodies', () {
      final config = LoggerConfig(maxBodyLength: 20);
      final longBody = 'a' * 100;

      final truncated = config.truncateBody(longBody);

      expect(truncated.length, lessThan(100));
      expect(truncated, contains('[truncated]'));
    });

    test('truncateBody does not truncate short bodies', () {
      final config = LoggerConfig(maxBodyLength: 100);
      final shortBody = 'short';

      final truncated = config.truncateBody(shortBody);

      expect(truncated, equals('short'));
    });

    test('truncateBody handles null', () {
      final config = LoggerConfig();

      expect(config.truncateBody(null), equals('null'));
    });

    test('copyWith creates updated config', () {
      final config = LoggerConfig();
      final updated = config.copyWith(
        level: LogLevel.trace,
        logResponseHeaders: true,
      );

      expect(updated.level, equals(LogLevel.trace));
      expect(updated.logResponseHeaders, isTrue);
      expect(updated.enabled, equals(config.enabled));
    });
  });

  group('LoggerRequestExtension', () {
    test('recordStartTime stores timestamp', () {
      final options = RequestOptions(path: '/test');

      options.recordStartTime();

      expect(options.startTime, isNotNull);
      expect(options.startTime, isA<int>());
    });

    test('durationMs calculates elapsed time', () async {
      final options = RequestOptions(path: '/test');

      options.recordStartTime();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final duration = options.durationMs;
      expect(duration, isNotNull);
      expect(duration, greaterThanOrEqualTo(20));
    });

    test('durationMs returns null if not recorded', () {
      final options = RequestOptions(path: '/test');

      expect(options.durationMs, isNull);
    });
  });

  group('LoggerInterceptor', () {
    late List<LogEntry> capturedLogs;
    late LoggerInterceptor interceptor;

    setUp(() {
      capturedLogs = [];
      interceptor = LoggerInterceptor(
        config: LoggerConfig(
          logHandler: (entry) => capturedLogs.add(entry),
        ),
      );
    });

    test('logs request with method and URL', () {
      final options = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.com',
      );
      final handler = _MockRequestHandler();

      interceptor.onRequest(options, handler);

      expect(capturedLogs.length, equals(1));
      expect(capturedLogs[0].method, equals('GET'));
      expect(capturedLogs[0].url, contains('/users'));
      expect(capturedLogs[0].message, equals('→ Request'));
    });

    test('logs request headers when enabled', () {
      final options = RequestOptions(
        path: '/users',
        headers: {'X-Custom': 'value', 'Authorization': 'Bearer token'},
      );
      final handler = _MockRequestHandler();

      interceptor.onRequest(options, handler);

      expect(capturedLogs[0].headers, isNotNull);
      expect(capturedLogs[0].headers!['X-Custom'], equals('value'));
      expect(capturedLogs[0].headers!['Authorization'], equals('[REDACTED]'));
    });

    test('logs request body when enabled', () {
      final options = RequestOptions(
        path: '/users',
        data: <String, dynamic>{'name': 'John'},
      );
      final handler = _MockRequestHandler();

      interceptor.onRequest(options, handler);

      expect(capturedLogs[0].body, equals({'name': 'John'}));
    });

    test('does not log headers when disabled', () {
      interceptor = LoggerInterceptor(
        config: LoggerConfig(
          logRequestHeaders: false,
          logHandler: (entry) => capturedLogs.add(entry),
        ),
      );

      final options = RequestOptions(
        path: '/users',
        headers: {'X-Custom': 'value'},
      );
      final handler = _MockRequestHandler();

      interceptor.onRequest(options, handler);

      expect(capturedLogs[0].headers, isNull);
    });

    test('logs response with status and duration', () {
      final options = RequestOptions(path: '/users');
      options.recordStartTime();

      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{'id': 1},
      );
      final handler = _MockResponseHandler();

      interceptor.onResponse(response, handler);

      expect(capturedLogs.length, equals(1));
      expect(capturedLogs[0].statusCode, equals(200));
      expect(capturedLogs[0].durationMs, isNotNull);
      expect(capturedLogs[0].message, equals('← Response'));
    });

    test('logs response body when enabled', () {
      final options = RequestOptions(path: '/users');
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{'id': 1},
      );
      final handler = _MockResponseHandler();

      interceptor.onResponse(response, handler);

      expect(capturedLogs[0].body, equals({'id': 1}));
    });

    test('logs error with type and message', () {
      final options = RequestOptions(path: '/users');
      options.recordStartTime();

      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timed out',
      );
      final handler = _MockErrorHandler();

      interceptor.onError(error, handler);

      expect(capturedLogs.length, equals(1));
      expect(capturedLogs[0].level, equals(LogLevel.error));
      expect(capturedLogs[0].message, equals('✖ Error'));
      expect(capturedLogs[0].error, contains('Connection timed out'));
      expect(capturedLogs[0].extra!['type'], equals('connectionTimeout'));
    });

    test('does not log when disabled', () {
      interceptor = LoggerInterceptor(
        config: LoggerConfig(
          enabled: false,
          logHandler: (entry) => capturedLogs.add(entry),
        ),
      );

      final options = RequestOptions(path: '/users');
      final handler = _MockRequestHandler();

      interceptor.onRequest(options, handler);

      expect(capturedLogs, isEmpty);
    });

    test('does not log below configured level', () {
      interceptor = LoggerInterceptor(
        config: LoggerConfig(
          level: LogLevel.error,
          logHandler: (entry) => capturedLogs.add(entry),
        ),
      );

      final options = RequestOptions(path: '/users');
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
      );

      interceptor.onRequest(options, _MockRequestHandler());
      interceptor.onResponse(response, _MockResponseHandler());

      expect(capturedLogs, isEmpty);
    });

    test('passes request to next handler', () {
      final options = RequestOptions(path: '/users');
      final handler = _MockRequestHandler();

      interceptor.onRequest(options, handler);

      expect(handler.nextCalled, isTrue);
    });

    test('passes response to next handler', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/users'),
        statusCode: 200,
      );
      final handler = _MockResponseHandler();

      interceptor.onResponse(response, handler);

      expect(handler.nextCalled, isTrue);
    });

    test('passes error to next handler', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/users'),
        type: DioExceptionType.unknown,
      );
      final handler = _MockErrorHandler();

      interceptor.onError(error, handler);

      expect(handler.nextCalled, isTrue);
    });
  });
}

class _MockRequestHandler extends RequestInterceptorHandler {
  bool nextCalled = false;

  @override
  void next(RequestOptions options) {
    nextCalled = true;
  }
}

class _MockResponseHandler extends ResponseInterceptorHandler {
  bool nextCalled = false;

  @override
  void next(Response<dynamic> response) {
    nextCalled = true;
  }
}

class _MockErrorHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;

  @override
  void next(DioException err) {
    nextCalled = true;
  }
}
