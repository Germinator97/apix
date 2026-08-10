import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('ErrorTrackingConfig', () {
    test('creates with default values', () {
      const config = ErrorTrackingConfig();

      expect(config.enabled, isTrue);
      expect(config.captureStatusCodes, equals({500, 501, 502, 503, 504}));
      expect(config.captureRequestBody, isFalse);
      expect(config.captureResponseBody, isTrue);
    });

    test('disabled factory creates disabled config', () {
      final config = ErrorTrackingConfig.disabled();

      expect(config.enabled, isFalse);
    });

    test('redactHeaders redacts sensitive headers', () {
      const config = ErrorTrackingConfig();
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
      const config = ErrorTrackingConfig(maxBodyLength: 20);
      final longBody = 'a' * 100;

      final truncated = config.truncateBody(longBody);

      expect(truncated.length, lessThan(100));
      expect(truncated, contains('[truncated]'));
    });
  });

  group('HttpTrackingException', () {
    test('toString formats correctly', () {
      const exception = HttpTrackingException(
        statusCode: 500,
        message: 'Internal Server Error',
        url: 'https://api.com/users',
        method: 'GET',
      );

      expect(
        exception.toString(),
        equals(
            'HttpTrackingException: GET https://api.com/users [500] Internal Server Error'),
      );
    });

    test('belongs to the documented exception hierarchy', () {
      const exception = HttpTrackingException(
        statusCode: 503,
        message: 'Service Unavailable',
        url: 'https://api.com/users',
        method: 'GET',
      );

      expect(exception, isA<HttpException>());
      expect(exception, isA<ApiException>());
      expect(exception.statusCode, equals(503));
    });
  });

  group('ErrorTrackingInterceptor', () {
    late List<Map<String, dynamic>> breadcrumbs;
    late List<CapturedError> capturedErrors;
    late ErrorTrackingInterceptor interceptor;

    setUp(() {
      breadcrumbs = [];
      capturedErrors = [];
      interceptor = ErrorTrackingInterceptor(
        config: ErrorTrackingConfig(
          environment: 'test',
          onError: (Object exception,
              {StackTrace? stackTrace,
              Map<String, dynamic>? extra,
              Map<String, String>? tags}) async {
            capturedErrors.add(CapturedError(
              exception: exception,
              stackTrace: stackTrace,
              extra: extra,
              tags: tags,
            ));
          },
          onBreadcrumb: (Map<String, dynamic> data) => breadcrumbs.add(data),
        ),
      );
    });

    // The defect this group pins down: `onError` has two call sites, and they
    // used to hand the callback two unrelated types. A handler written from the
    // documentation matched one and fell through the other in silence — no
    // throw, no log, just a branch that never fired. Both directions are
    // asserted here because fixing only the type would still leave the
    // onResponse path without a stack trace.
    group('onError receives one type on both paths', () {
      /// The handler shape the documentation tells consumers to write.
      String? screenFor(Object exception) => switch (exception) {
            HttpException(statusCode: 503) => 'service-unavailable',
            HttpException(statusCode: final int s) when s >= 500 =>
              'server-error',
            _ => null,
          };

      test('via onError — a DioException reported by dio', () {
        final options = RequestOptions(path: '/users', method: 'GET');
        interceptor.onError(
          DioException(
            type: DioExceptionType.badResponse,
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 503,
              data: {'message': 'Down for maintenance'},
            ),
          ),
          _MockErrorHandler(),
        );

        expect(capturedErrors, hasLength(1));
        expect(capturedErrors[0].exception, isA<ApiException>());
        expect(
            screenFor(capturedErrors[0].exception),
            equals(
              'service-unavailable',
            ));
      });

      test('via onResponse — a status the consumer asked to capture', () {
        final options = RequestOptions(path: '/users', method: 'GET');
        interceptor.onResponse(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 503,
            statusMessage: 'Service Unavailable',
          ),
          _MockResponseHandler(),
        );

        expect(capturedErrors, hasLength(1));
        expect(
          capturedErrors[0].exception,
          isA<ApiException>(),
          reason: 'ErrorTrackingConfig.onError documents a typed ApiException; '
              'this path used to hand over a bare Exception instead',
        );
        expect(
          screenFor(capturedErrors[0].exception),
          equals('service-unavailable'),
          reason: 'the same handler must fire on both paths — this is the '
              'branch that used to die silently',
        );
      });

      test('the onResponse path carries a stack trace', () {
        final options = RequestOptions(path: '/users', method: 'GET');
        interceptor.onResponse(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 500,
            statusMessage: 'Internal Server Error',
          ),
          _MockResponseHandler(),
        );

        expect(
          capturedErrors[0].stackTrace,
          isNotNull,
          reason: 'without one, these events land in the tracker with no stack '
              'while the onError path always had one',
        );
      });
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

    test('reports the mapped ApiException, not the raw DioException', () {
      // Trackers group issues by the exception's runtime type. Reporting
      // DioException filed every 500, 404 and timeout under one issue, and
      // left type-based noise filtering nothing to work with.
      final options = RequestOptions(path: '/fail', method: 'POST');
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timed out',
      );
      final handler = _MockErrorHandler();

      interceptor.onError(error, handler);

      expect(capturedErrors.length, equals(1));
      final reported = capturedErrors[0].exception;
      expect(reported, isA<TimeoutException>());
      expect(reported, isNot(isA<DioException>()));
      // Nothing is lost: the DioException is still reachable.
      expect((reported as ApiException).originalError, same(error));

      expect(capturedErrors[0].extra, isNotNull);
      expect(capturedErrors[0].extra!['method'], equals('POST'));
      expect(capturedErrors[0].tags, isNotNull);
      expect(capturedErrors[0].tags!['http.method'], equals('POST'));
    });

    test('an HTTP failure is reported with its status-specific type', () {
      // The point of the change: a 500 and a 404 must land as different types
      // so a tracker files them as different issues instead of collapsing
      // both into one titled `DioException`.
      //
      // captureStatusCodes is widened here on purpose — 404 is outside the
      // default set, and skipping it on an empty capture would leave this
      // test silently proving half of what it claims.
      final reported = <Object>[];
      final wide = ErrorTrackingInterceptor(
        config: ErrorTrackingConfig(
          captureStatusCodes: const {404, 500},
          onError: (Object exception,
              {StackTrace? stackTrace,
              Map<String, dynamic>? extra,
              Map<String, String>? tags}) async {
            reported.add(exception);
          },
        ),
      );

      for (final status in [500, 404]) {
        final options = RequestOptions(path: '/x', method: 'GET');
        wide.onError(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: status,
              data: {'message': 'boom'},
            ),
          ),
          _MockErrorHandler(),
        );
      }

      expect(reported, hasLength(2), reason: 'both statuses must be captured');
      expect(reported[0], isA<ServerException>());
      expect(reported[1], isA<NotFoundException>());
      expect(
        reported[0].runtimeType,
        isNot(reported[1].runtimeType),
        reason: 'distinct types are what makes a tracker group them apart',
      );
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
      expect(capturedErrors[0].exception, isA<HttpTrackingException>());
      final httpError = capturedErrors[0].exception as HttpTrackingException;
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
      interceptor = ErrorTrackingInterceptor(
        config: ErrorTrackingConfig(
          onError: (Object exception,
              {StackTrace? stackTrace,
              Map<String, dynamic>? extra,
              Map<String, String>? tags}) async {
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
      interceptor = ErrorTrackingInterceptor(
        config: ErrorTrackingConfig(
          enabled: false,
          onError: (Object exception,
              {StackTrace? stackTrace,
              Map<String, dynamic>? extra,
              Map<String, String>? tags}) async {
            capturedErrors.add(CapturedError(exception: exception));
          },
          onBreadcrumb: (Map<String, dynamic> data) => breadcrumbs.add(data),
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
      interceptor = ErrorTrackingInterceptor(
        config: ErrorTrackingConfig(
          captureStatusCodes: {400, 401, 403, 404, 500},
          onError: (Object exception,
              {StackTrace? stackTrace,
              Map<String, dynamic>? extra,
              Map<String, String>? tags}) async {
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
      final httpError = capturedErrors[0].exception as HttpTrackingException;
      expect(httpError.statusCode, equals(403));
    });

    test('captures badResponse errors matching captureStatusCodes', () {
      final options = RequestOptions(path: '/error');
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options,
          statusCode: 500,
        ),
      );

      interceptor.onError(error, _MockErrorHandler());

      expect(capturedErrors.length, equals(1));
    });

    test('does not capture badResponse errors outside captureStatusCodes', () {
      final options = RequestOptions(path: '/unauthorized');
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options,
          statusCode: 401,
        ),
      );

      interceptor.onError(error, _MockErrorHandler());

      expect(capturedErrors, isEmpty);
    });

    test('always captures non-HTTP errors regardless of captureStatusCodes',
        () {
      final types = [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.cancel,
        DioExceptionType.unknown,
      ];

      for (final type in types) {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: type,
        );
        interceptor.onError(error, _MockErrorHandler());
      }

      expect(capturedErrors.length, equals(types.length));
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
