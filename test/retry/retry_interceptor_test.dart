import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('RetryConfig', () {
    test('creates with default values', () {
      const config = RetryConfig();

      expect(config.maxAttempts, equals(3));
      expect(config.retryStatusCodes, equals([500, 502, 503, 504]));
      expect(config.baseDelayMs, equals(1000));
      expect(config.multiplier, equals(2.0));
    });

    test('creates with custom values', () {
      const config = RetryConfig(
        maxAttempts: 5,
        retryStatusCodes: [500, 503],
        baseDelayMs: 500,
        multiplier: 1.5,
      );

      expect(config.maxAttempts, equals(5));
      expect(config.retryStatusCodes, equals([500, 503]));
      expect(config.baseDelayMs, equals(500));
      expect(config.multiplier, equals(1.5));
    });

    test('shouldRetry returns true for configured status codes', () {
      const config = RetryConfig(retryStatusCodes: [500, 502, 503]);

      expect(config.shouldRetry(500), isTrue);
      expect(config.shouldRetry(502), isTrue);
      expect(config.shouldRetry(503), isTrue);
    });

    test('shouldRetry returns false for non-configured status codes', () {
      const config = RetryConfig(retryStatusCodes: [500, 502, 503]);

      expect(config.shouldRetry(400), isFalse);
      expect(config.shouldRetry(401), isFalse);
      expect(config.shouldRetry(404), isFalse);
      expect(config.shouldRetry(504), isFalse);
    });

    test('getDelay calculates exponential backoff', () {
      const config = RetryConfig(baseDelayMs: 1000, multiplier: 2.0);

      expect(config.getDelay(0), equals(const Duration(milliseconds: 1000)));
      expect(config.getDelay(1), equals(const Duration(milliseconds: 2000)));
      expect(config.getDelay(2), equals(const Duration(milliseconds: 4000)));
      expect(config.getDelay(3), equals(const Duration(milliseconds: 8000)));
    });

    test('getDelay with custom multiplier', () {
      const config = RetryConfig(baseDelayMs: 100, multiplier: 3.0);

      expect(config.getDelay(0), equals(const Duration(milliseconds: 100)));
      expect(config.getDelay(1), equals(const Duration(milliseconds: 300)));
      expect(config.getDelay(2), equals(const Duration(milliseconds: 900)));
    });

    test('copyWith creates new config with updated values', () {
      const original = RetryConfig();
      final updated = original.copyWith(maxAttempts: 5);

      expect(updated.maxAttempts, equals(5));
      expect(updated.retryStatusCodes, equals(original.retryStatusCodes));
      expect(updated.baseDelayMs, equals(original.baseDelayMs));
      expect(updated.multiplier, equals(original.multiplier));
    });

    test('equality works correctly', () {
      const config1 = RetryConfig(maxAttempts: 3);
      const config2 = RetryConfig(maxAttempts: 3);
      const config3 = RetryConfig(maxAttempts: 5);

      expect(config1, equals(config2));
      expect(config1, isNot(equals(config3)));
    });

    test('toString returns readable representation', () {
      const config = RetryConfig();
      final str = config.toString();

      expect(str, contains('maxAttempts: 3'));
      expect(str, contains('retryStatusCodes'));
    });
  });

  group('RetryInterceptor', () {
    late Dio dio;
    late RetryConfig config;

    setUp(() {
      dio = Dio();
      config = const RetryConfig(
        maxAttempts: 3,
        baseDelayMs: 10, // Fast delays for testing
      );
    });

    test('passes through non-retryable status codes', () async {
      final interceptor = RetryInterceptor(config: config, dio: dio);
      final handler = TestErrorHandler();

      final error = DioException(
        requestOptions: RequestOptions(path: '/api/users'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/users'),
          statusCode: 404,
        ),
      );

      interceptor.onError(error, handler);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.nextCalled, isTrue);
    });

    test('passes through when no status code', () async {
      final interceptor = RetryInterceptor(config: config, dio: dio);
      final handler = TestErrorHandler();

      final error = DioException(
        requestOptions: RequestOptions(path: '/api/users'),
        type: DioExceptionType.connectionTimeout,
      );

      interceptor.onError(error, handler);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.nextCalled, isTrue);
    });

    test('respects noRetry flag', () async {
      final interceptor = RetryInterceptor(config: config, dio: dio);
      final handler = TestErrorHandler();

      final requestOptions = RequestOptions(path: '/api/users');
      requestOptions.disableRetry();

      final error = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 500,
        ),
      );

      interceptor.onError(error, handler);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.nextCalled, isTrue);
    });

    test('increments attempt count on retry', () async {
      final interceptor = RetryInterceptor(config: config, dio: dio);
      final handler = TestErrorHandler();

      final requestOptions = RequestOptions(path: '/api/users');

      final error = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 500,
        ),
      );

      // First call - should trigger retry
      interceptor.onError(error, handler);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // After first onError, attempt should be incremented
      expect(requestOptions.extra['_retryAttempt'], equals(1));
    });
  });

  group('NoRetryExtension', () {
    test('disableRetry marks request as non-retryable', () {
      final options = RequestOptions(path: '/api/users');

      expect(options.isNoRetry, isFalse);

      options.disableRetry();

      expect(options.isNoRetry, isTrue);
      expect(options.extra[noRetryKey], isTrue);
    });
  });
}

class TestErrorHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;
  bool resolveCalled = false;
  bool rejectCalled = false;
  DioException? lastError;
  DioException? lastRejectedError;
  Response<dynamic>? lastResponse;

  @override
  void next(DioException err) {
    nextCalled = true;
    lastError = err;
  }

  @override
  void resolve(Response<dynamic> response) {
    resolveCalled = true;
    lastResponse = response;
  }

  @override
  void reject(DioException err) {
    rejectCalled = true;
    lastRejectedError = err;
  }
}
