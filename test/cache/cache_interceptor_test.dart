import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('CacheInterceptor', () {
    late InMemoryCacheStorage storage;
    late CacheConfig config;
    late CacheInterceptor interceptor;

    setUp(() {
      storage = InMemoryCacheStorage();
      config = CacheConfig(
        storage: storage,
        strategy: CacheStrategy.networkFirst,
        defaultTtl: const Duration(minutes: 5),
      );
      interceptor = CacheInterceptor(config: config);
    });

    group('CacheFirst strategy', () {
      setUp(() {
        config = CacheConfig(
          storage: storage,
          strategy: CacheStrategy.cacheFirst,
        );
        interceptor = CacheInterceptor(config: config);
      });

      test('returns cached response if available', () async {
        // Pre-populate cache
        final entry = CacheEntry.withTtl(
          data: '{"id": 1}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
        );
        await storage.set('GET:https://api.test.com/users', entry);

        final handler = TestRequestHandler();
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.resolvedResponse, isNotNull);
        expect(handler.resolvedResponse!.data, equals({'id': 1}));
        expect(handler.resolvedResponse!.extra['fromCache'], isTrue);
      });

      test('proceeds with network if cache miss', () async {
        final handler = TestRequestHandler();
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.nextCalled, isTrue);
      });
    });

    group('NetworkFirst strategy', () {
      test('caches successful response', () async {
        final handler = TestResponseHandler();
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );

        final response = Response<dynamic>(
          requestOptions: options,
          data: {'id': 1},
          statusCode: 200,
        );

        interceptor.onResponse(response, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.nextCalled, isTrue);
        expect(await storage.has('GET:https://api.test.com/users'), isTrue);
      });

      test('falls back to cache on network error', () async {
        // Pre-populate cache
        final entry = CacheEntry.withTtl(
          data: '{"id": 1}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
        );
        await storage.set('GET:https://api.test.com/users', entry);

        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );
        options.extra['_cacheKey'] = 'GET:https://api.test.com/users';

        final handler = TestErrorHandler();
        final error = DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );

        interceptor.onError(error, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.resolvedResponse, isNotNull);
        expect(handler.resolvedResponse!.data, equals({'id': 1}));
      });

      test('propagates error if no cache available', () async {
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );
        options.extra['_cacheKey'] = 'GET:https://api.test.com/users';

        final handler = TestErrorHandler();
        final error = DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );

        interceptor.onError(error, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.nextCalled, isTrue);
      });
    });

    group('CacheOnly strategy', () {
      setUp(() {
        config = CacheConfig(
          storage: storage,
          strategy: CacheStrategy.cacheOnly,
        );
        interceptor = CacheInterceptor(config: config);
      });

      test('returns cached response', () async {
        final entry = CacheEntry.withTtl(
          data: '{"id": 1}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
        );
        await storage.set('GET:https://api.test.com/users', entry);

        final handler = TestRequestHandler();
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.resolvedResponse, isNotNull);
      });

      test('rejects if no cache available', () async {
        final handler = TestRequestHandler();
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.rejectedError, isNotNull);
        expect(handler.rejectedError!.error, isA<CacheException>());
      });
    });

    group('Non-cacheable methods', () {
      test('POST requests are not cached by default', () async {
        final handler = TestRequestHandler();
        final options = RequestOptions(
          path: '/users',
          method: 'POST',
          baseUrl: 'https://api.test.com',
        );

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.nextCalled, isTrue);
      });
    });

    group('Per-request cache control', () {
      test('setCacheStrategy overrides config strategy', () async {
        // Config is networkFirst but we override to cacheOnly
        final entry = CacheEntry.withTtl(
          data: '{"id": 1}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
        );
        await storage.set('GET:https://api.test.com/users', entry);

        final handler = TestRequestHandler();
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );
        options.setCacheStrategy(CacheStrategy.cacheFirst);

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.resolvedResponse, isNotNull);
        expect(handler.resolvedResponse!.extra['fromCache'], isTrue);
      });

      test('noCache forces network request', () async {
        final entry = CacheEntry.withTtl(
          data: '{"id": 1}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
        );
        await storage.set('GET:https://api.test.com/users', entry);

        config = CacheConfig(
          storage: storage,
          strategy: CacheStrategy.cacheFirst,
        );
        interceptor = CacheInterceptor(config: config);

        final handler = TestRequestHandler();
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );
        options.noCache();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // networkOnly goes to next, not resolve
        expect(handler.nextCalled, isTrue);
      });
    });

    group('Cache key generation', () {
      test('includes query parameters in cache key', () async {
        final handler = TestResponseHandler();
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
          queryParameters: {'page': 1, 'limit': 10},
        );

        final response = Response<dynamic>(
          requestOptions: options,
          data: <String, dynamic>{'users': <dynamic>[]},
          statusCode: 200,
        );

        interceptor.onResponse(response, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final keys = await storage.keys();
        expect(keys.first, contains('page'));
        expect(keys.first, contains('limit'));
      });
    });
  });

  group('CacheException', () {
    test('toString returns message', () {
      const exception = CacheException('Test error');
      expect(exception.toString(), equals('CacheException: Test error'));
    });
  });

  group('CacheRequestExtension', () {
    test('isFromCache detects cached response', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        data: <String, dynamic>{},
        extra: <String, dynamic>{'fromCache': true},
      );

      expect(CacheRequestExtension.isFromCache(response), isTrue);
    });

    test('isFromCache returns false for network response', () {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/test'),
        data: <String, dynamic>{},
      );

      expect(CacheRequestExtension.isFromCache(response), isFalse);
    });
  });
}

class TestRequestHandler extends RequestInterceptorHandler {
  bool nextCalled = false;
  Response<dynamic>? resolvedResponse;
  DioException? rejectedError;

  @override
  void next(RequestOptions options) {
    nextCalled = true;
  }

  @override
  void resolve(Response<dynamic> response,
      [bool callFollowingResponseInterceptor = false]) {
    resolvedResponse = response;
  }

  @override
  void reject(DioException error,
      [bool callFollowingErrorInterceptor = false]) {
    rejectedError = error;
  }
}

class TestResponseHandler extends ResponseInterceptorHandler {
  bool nextCalled = false;
  Response<dynamic>? lastResponse;

  @override
  void next(Response<dynamic> response) {
    nextCalled = true;
    lastResponse = response;
  }
}

class TestErrorHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;
  Response<dynamic>? resolvedResponse;
  DioException? lastError;

  @override
  void next(DioException err) {
    nextCalled = true;
    lastError = err;
  }

  @override
  void resolve(Response<dynamic> response) {
    resolvedResponse = response;
  }
}
