import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('SentryConfig', () {
    test('creates with default values', () {
      const config = SentryConfig();

      expect(config.enabled, isTrue);
      expect(config.captureStatusCodes, equals({500, 501, 502, 503, 504}));
      expect(config.captureRequestBody, isFalse);
      expect(config.captureResponseBody, isTrue);
    });

    test('disabled factory creates disabled config', () {
      final config = SentryConfig.disabled();

      expect(config.enabled, isFalse);
    });

    test('redactHeaders redacts sensitive headers', () {
      const config = SentryConfig();
      final headers = <String, dynamic>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer secret',
        'Cookie': 'session=abc',
      };

      final redacted = config.redactHeaders(headers);

      expect(redacted['Content-Type'], equals('application/json'));
      expect(redacted['Authorization'], equals('[REDACTED]'));
      expect(redacted['Cookie'], equals('[REDACTED]'));
    });

    test('truncateBody truncates long bodies', () {
      const config = SentryConfig(maxBodyLength: 20);
      final longBody = 'a' * 100;

      final truncated = config.truncateBody(longBody);

      expect(truncated.length, lessThan(100));
      expect(truncated, contains('[truncated]'));
    });
  });

  group('SentryHttpException', () {
    test('toString formats correctly', () {
      const exception = SentryHttpException(
        statusCode: 500,
        message: 'Internal Server Error',
        url: 'https://api.com/users',
        method: 'GET',
      );

      expect(
        exception.toString(),
        equals(
            'SentryHttpException: GET https://api.com/users [500] Internal Server Error'),
      );
    });
  });

  group('SentryInterceptor', () {
    late List<Map<String, dynamic>> breadcrumbs;
    late List<CapturedError> capturedErrors;
    late SentryInterceptor interceptor;

    setUp(() {
      breadcrumbs = [];
      capturedErrors = [];
      interceptor = SentryInterceptor(
        config: SentryConfig(
          environment: 'test',
          captureException: (exception, {stackTrace, extra, tags}) async {
            capturedErrors.add(CapturedError(
              exception: exception,
              stackTrace: stackTrace,
              extra: extra,
              tags: tags,
            ));
          },
          addBreadcrumb: (data) => breadcrumbs.add(data),
        ),
      );
    });

    test('adds request breadcrumb', () {
      final options = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.com',
      );
      final handler = _MockRequestHandler();

      interceptor.onRequest(options, handler);

      expect(breadcrumbs.length, equals(1));
      expect(breadcrumbs[0]['category'], equals('http'));
      expect(breadcrumbs[0]['message'], contains('GET'));
      expect(breadcrumbs[0]['message'], contains('/users'));
    });

    test('adds response breadcrumb', () {
      final options = RequestOptions(path: '/users', method: 'GET');
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        statusMessage: 'OK',
      );
      final handler = _MockResponseHandler();

      interceptor.onResponse(response, handler);

      expect(breadcrumbs.length, equals(1));
      expect(breadcrumbs[0]['message'], contains('[200]'));
      expect((breadcrumbs[0]['data'] as Map<String, dynamic>)['status_code'],
          equals(200));
    });

    test('captures DioException errors', () {
      final options = RequestOptions(path: '/fail', method: 'POST');
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timed out',
      );
      final handler = _MockErrorHandler();

      interceptor.onError(error, handler);

      expect(capturedErrors.length, equals(1));
      expect(capturedErrors[0].exception, isA<DioException>());
      expect(capturedErrors[0].extra, isNotNull);
      expect(capturedErrors[0].extra!['method'], equals('POST'));
      expect(capturedErrors[0].tags, isNotNull);
      expect(capturedErrors[0].tags!['http.method'], equals('POST'));
    });

    test('captures 5xx status codes as errors', () {
      final options = RequestOptions(path: '/error', method: 'GET');
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 500,
        statusMessage: 'Internal Server Error',
      );
      final handler = _MockResponseHandler();

      interceptor.onResponse(response, handler);

      expect(capturedErrors.length, equals(1));
      expect(capturedErrors[0].exception, isA<SentryHttpException>());
      final httpError = capturedErrors[0].exception as SentryHttpException;
      expect(httpError.statusCode, equals(500));
    });

    test('does not capture 4xx status codes by default', () {
      final options = RequestOptions(path: '/notfound', method: 'GET');
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 404,
        statusMessage: 'Not Found',
      );
      final handler = _MockResponseHandler();

      interceptor.onResponse(response, handler);

      expect(capturedErrors, isEmpty);
    });

    test('includes environment in error context', () {
      final options = RequestOptions(path: '/error');
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
      );

      interceptor.onError(error, _MockErrorHandler());

      expect(capturedErrors[0].extra!['environment'], equals('test'));
      expect(capturedErrors[0].tags!['environment'], equals('test'));
    });

    test('redacts sensitive headers in error context', () {
      interceptor = SentryInterceptor(
        config: SentryConfig(
          captureException: (exception, {stackTrace, extra, tags}) async {
            capturedErrors.add(CapturedError(
              exception: exception,
              extra: extra,
              tags: tags,
            ));
          },
        ),
      );

      final options = RequestOptions(
        path: '/error',
        headers: {'Authorization': 'Bearer secret'},
      );
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
      );

      interceptor.onError(error, _MockErrorHandler());

      final headers = capturedErrors[0].extra!['headers'] as Map;
      expect(headers['Authorization'], equals('[REDACTED]'));
    });

    test('does not capture when disabled', () {
      interceptor = SentryInterceptor(
        config: SentryConfig(
          enabled: false,
          captureException: (exception, {stackTrace, extra, tags}) async {
            capturedErrors.add(CapturedError(exception: exception));
          },
          addBreadcrumb: (data) => breadcrumbs.add(data),
        ),
      );

      final options = RequestOptions(path: '/test');
      interceptor.onRequest(options, _MockRequestHandler());

      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
      );
      interceptor.onError(error, _MockErrorHandler());

      expect(breadcrumbs, isEmpty);
      expect(capturedErrors, isEmpty);
    });

    test('passes request to next handler', () {
      final options = RequestOptions(path: '/test');
      final handler = _MockRequestHandler();

      interceptor.onRequest(options, handler);

      expect(handler.nextCalled, isTrue);
    });

    test('passes response to next handler', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 200,
      );
      final handler = _MockResponseHandler();

      interceptor.onResponse(response, handler);

      expect(handler.nextCalled, isTrue);
    });

    test('passes error to next handler', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.unknown,
      );
      final handler = _MockErrorHandler();

      interceptor.onError(error, handler);

      expect(handler.nextCalled, isTrue);
    });

    test('captures custom status codes when configured', () {
      interceptor = SentryInterceptor(
        config: SentryConfig(
          captureStatusCodes: {400, 401, 403, 404, 500},
          captureException: (exception, {stackTrace, extra, tags}) async {
            capturedErrors.add(CapturedError(exception: exception));
          },
        ),
      );

      final options = RequestOptions(path: '/forbidden');
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 403,
        statusMessage: 'Forbidden',
      );

      interceptor.onResponse(response, _MockResponseHandler());

      expect(capturedErrors.length, equals(1));
      final httpError = capturedErrors[0].exception as SentryHttpException;
      expect(httpError.statusCode, equals(403));
    });
  });
}

class CapturedError {
  final Object exception;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? extra;
  final Map<String, String>? tags;

  CapturedError({
    required this.exception,
    this.stackTrace,
    this.extra,
    this.tags,
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
