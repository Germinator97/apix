import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('RequestMetrics', () {
    test('creates with required fields', () {
      final metrics = RequestMetrics(
        requestId: '123',
        method: 'GET',
        url: 'https://api.com/users',
        path: '/users',
        startTime: DateTime(2024, 1, 1, 12, 0, 0),
      );

      expect(metrics.requestId, equals('123'));
      expect(metrics.method, equals('GET'));
      expect(metrics.success, isTrue);
    });

    test('copyWith creates updated copy', () {
      final metrics = RequestMetrics(
        requestId: '123',
        method: 'GET',
        url: 'https://api.com/users',
        path: '/users',
        startTime: DateTime(2024, 1, 1, 12, 0, 0),
      );

      final completed = metrics.copyWith(
        endTime: DateTime(2024, 1, 1, 12, 0, 1),
        durationMs: 1000,
        statusCode: 200,
      );

      expect(completed.durationMs, equals(1000));
      expect(completed.statusCode, equals(200));
      expect(completed.requestId, equals('123'));
    });

    test('toMap includes all fields', () {
      final metrics = RequestMetrics(
        requestId: '123',
        method: 'GET',
        url: 'https://api.com/users',
        path: '/users',
        startTime: DateTime(2024, 1, 1, 12, 0, 0),
        endTime: DateTime(2024, 1, 1, 12, 0, 1),
        durationMs: 1000,
        statusCode: 200,
        success: true,
      );

      final map = metrics.toMap();

      expect(map['request_id'], equals('123'));
      expect(map['method'], equals('GET'));
      expect(map['duration_ms'], equals(1000));
      expect(map['status_code'], equals(200));
      expect(map['success'], isTrue);
    });

    test('toString formats correctly', () {
      final metrics = RequestMetrics(
        requestId: '123',
        method: 'POST',
        url: 'https://api.com/users',
        path: '/users',
        startTime: DateTime.now(),
        durationMs: 150,
        statusCode: 201,
      );

      expect(metrics.toString(), contains('POST'));
      expect(metrics.toString(), contains('/users'));
      expect(metrics.toString(), contains('[201]'));
      expect(metrics.toString(), contains('150ms'));
    });
  });

  group('RequestBreadcrumb', () {
    test('creates with required fields', () {
      final breadcrumb = RequestBreadcrumb(
        type: BreadcrumbType.request,
        message: '→ GET /users',
        category: 'http',
        timestamp: DateTime.now(),
      );

      expect(breadcrumb.type, equals(BreadcrumbType.request));
      expect(breadcrumb.category, equals('http'));
    });

    test('toMap converts correctly', () {
      final breadcrumb = RequestBreadcrumb(
        type: BreadcrumbType.response,
        message: '← GET /users [200]',
        category: 'http',
        timestamp: DateTime(2024, 1, 1),
        data: {'status_code': 200},
      );

      final map = breadcrumb.toMap();

      expect(map['type'], equals('response'));
      expect(map['message'], equals('← GET /users [200]'));
      expect((map['data'] as Map<String, dynamic>)['status_code'], equals(200));
    });
  });

  group('MetricsConfig', () {
    test('creates with default values', () {
      const config = MetricsConfig();

      expect(config.enabled, isTrue);
      expect(config.trackRequestSize, isFalse);
      expect(config.trackResponseSize, isFalse);
    });

    test('disabled factory creates disabled config', () {
      final config = MetricsConfig.disabled();

      expect(config.enabled, isFalse);
    });
  });

  group('MetricsInterceptor', () {
    late List<RequestMetrics> capturedMetrics;
    late List<RequestBreadcrumb> capturedBreadcrumbs;
    late MetricsInterceptor interceptor;

    setUp(() {
      capturedMetrics = [];
      capturedBreadcrumbs = [];
      interceptor = MetricsInterceptor(
        config: MetricsConfig(
          onMetrics: (m) => capturedMetrics.add(m),
          onBreadcrumb: (b) => capturedBreadcrumbs.add(b),
        ),
      );
    });

    test('creates request breadcrumb on request', () {
      final options = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.com',
      );
      final handler = _MockRequestHandler();

      interceptor.onRequest(options, handler);

      expect(capturedBreadcrumbs.length, equals(1));
      expect(capturedBreadcrumbs[0].type, equals(BreadcrumbType.request));
      expect(capturedBreadcrumbs[0].message, contains('GET'));
      expect(capturedBreadcrumbs[0].message, contains('/users'));
    });

    test('tracks in-flight requests', () {
      final options = RequestOptions(path: '/users');

      interceptor.onRequest(options, _MockRequestHandler());

      expect(interceptor.inFlightCount, equals(1));
    });

    test('creates response breadcrumb on response', () {
      final options = RequestOptions(path: '/users', method: 'GET');
      interceptor.onRequest(options, _MockRequestHandler());

      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
      );
      interceptor.onResponse(response, _MockResponseHandler());

      expect(capturedBreadcrumbs.length, equals(2));
      expect(capturedBreadcrumbs[1].type, equals(BreadcrumbType.response));
      expect(capturedBreadcrumbs[1].message, contains('[200]'));
    });

    test('emits metrics on response', () {
      final options = RequestOptions(path: '/users', method: 'GET');
      interceptor.onRequest(options, _MockRequestHandler());

      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
      );
      interceptor.onResponse(response, _MockResponseHandler());

      expect(capturedMetrics.length, equals(1));
      expect(capturedMetrics[0].method, equals('GET'));
      expect(capturedMetrics[0].statusCode, equals(200));
      expect(capturedMetrics[0].success, isTrue);
      expect(capturedMetrics[0].durationMs, isNotNull);
    });

    test('removes completed request from in-flight', () {
      final options = RequestOptions(path: '/users');
      interceptor.onRequest(options, _MockRequestHandler());

      expect(interceptor.inFlightCount, equals(1));

      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
      );
      interceptor.onResponse(response, _MockResponseHandler());

      expect(interceptor.inFlightCount, equals(0));
    });

    test('creates error breadcrumb on error', () {
      final options = RequestOptions(path: '/fail', method: 'POST');
      interceptor.onRequest(options, _MockRequestHandler());

      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timed out',
      );
      interceptor.onError(error, _MockErrorHandler());

      expect(capturedBreadcrumbs.length, equals(2));
      expect(capturedBreadcrumbs[1].type, equals(BreadcrumbType.error));
      expect(capturedBreadcrumbs[1].message, contains('connectionTimeout'));
    });

    test('emits metrics on error', () {
      final options = RequestOptions(path: '/fail', method: 'POST');
      interceptor.onRequest(options, _MockRequestHandler());

      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        message: 'Server error',
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 500,
        ),
      );
      interceptor.onError(error, _MockErrorHandler());

      expect(capturedMetrics.length, equals(1));
      expect(capturedMetrics[0].success, isFalse);
      expect(capturedMetrics[0].statusCode, equals(500));
      expect(capturedMetrics[0].errorType, equals('badResponse'));
      expect(capturedMetrics[0].error, contains('Server error'));
    });

    test('does not track when disabled', () {
      interceptor = MetricsInterceptor(
        config: MetricsConfig(
          enabled: false,
          onMetrics: (m) => capturedMetrics.add(m),
          onBreadcrumb: (b) => capturedBreadcrumbs.add(b),
        ),
      );

      final options = RequestOptions(path: '/users');
      interceptor.onRequest(options, _MockRequestHandler());

      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
      );
      interceptor.onResponse(response, _MockResponseHandler());

      expect(capturedBreadcrumbs, isEmpty);
      expect(capturedMetrics, isEmpty);
      expect(interceptor.inFlightCount, equals(0));
    });

    test('uses custom request ID generator', () {
      var counter = 0;
      interceptor = MetricsInterceptor(
        config: MetricsConfig(
          requestIdGenerator: () => 'custom_${++counter}',
          onMetrics: (m) => capturedMetrics.add(m),
        ),
      );

      final options = RequestOptions(path: '/users');
      interceptor.onRequest(options, _MockRequestHandler());

      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
      );
      interceptor.onResponse(response, _MockResponseHandler());

      expect(capturedMetrics[0].requestId, equals('custom_1'));
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
