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

    group('HttpCacheAware strategy', () {
      setUp(() {
        config = CacheConfig(
          storage: storage,
          strategy: CacheStrategy.httpCacheAware,
        );
        interceptor = CacheInterceptor(config: config);
      });

      test('returns fresh cache without network request', () async {
        final entry = CacheEntry.withTtl(
          data: '{"id": 1}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
          etag: '"abc123"',
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
        expect(handler.resolvedResponse!.extra['fromCache'], isTrue);
      });

      test('adds If-None-Match header when forcing revalidation', () async {
        // Cache is valid but we force revalidation
        final entry = CacheEntry.withTtl(
          data: '{"id": 1}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
          etag: '"abc123"',
        );
        await storage.set('GET:https://api.test.com/users', entry);

        RequestOptions? capturedOptions;
        final handler = TestRequestHandlerWithCapture(
          onNext: (RequestOptions opts) => capturedOptions = opts,
        );
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );
        // Force revalidation even though cache is valid
        options.extra['_forceRevalidate'] = true;

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.nextCalled, isTrue);
        expect(capturedOptions?.headers['If-None-Match'], equals('"abc123"'));
      });

      test('handles 304 Not Modified by returning cached response', () async {
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

        final handler = TestResponseHandlerWithResolve();
        final response = Response<dynamic>(
          requestOptions: options,
          statusCode: 304,
        );

        interceptor.onResponse(response, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.resolvedResponse, isNotNull);
        expect(handler.resolvedResponse!.data, equals({'id': 1}));
      });

      test('respects Cache-Control max-age for TTL', () async {
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );
        options.extra['_cacheKey'] = 'GET:https://api.test.com/users';

        final handler = TestResponseHandler();
        final response = Response<dynamic>(
          requestOptions: options,
          data: <String, dynamic>{'id': 1},
          statusCode: 200,
          headers: Headers.fromMap(<String, List<String>>{
            'cache-control': ['max-age=3600'],
          }),
        );

        interceptor.onResponse(response, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final cached = await storage.get('GET:https://api.test.com/users');
        expect(cached, isNotNull);
        // TTL should be ~1 hour (3600 seconds)
        expect(cached!.remainingTtl.inMinutes, greaterThan(55));
      });

      test('does not cache response with no-store directive', () async {
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );
        options.extra['_cacheKey'] = 'GET:https://api.test.com/users';

        final handler = TestResponseHandler();
        final response = Response<dynamic>(
          requestOptions: options,
          data: <String, dynamic>{'id': 1},
          statusCode: 200,
          headers: Headers.fromMap(<String, List<String>>{
            'cache-control': ['no-store'],
          }),
        );

        interceptor.onResponse(response, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(await storage.has('GET:https://api.test.com/users'), isFalse);
      });

      test('stores ETag from response headers', () async {
        final options = RequestOptions(
          path: '/users',
          method: 'GET',
          baseUrl: 'https://api.test.com',
        );
        options.extra['_cacheKey'] = 'GET:https://api.test.com/users';

        final handler = TestResponseHandler();
        final response = Response<dynamic>(
          requestOptions: options,
          data: <String, dynamic>{'id': 1},
          statusCode: 200,
          headers: Headers.fromMap(<String, List<String>>{
            'etag': ['"xyz789"'],
            'cache-control': ['max-age=300'],
          }),
        );

        interceptor.onResponse(response, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final cached = await storage.get('GET:https://api.test.com/users');
        expect(cached?.etag, equals('"xyz789"'));
      });

      test('falls back to cache on network error', () async {
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
    });
  });

  group('CacheControlHeader', () {
    test('parses max-age directive', () {
      const header = CacheControlHeader(maxAge: 3600);
      expect(header.maxAge, equals(3600));
      expect(header.noCache, isFalse);
      expect(header.noStore, isFalse);
    });

    test('toString returns readable format', () {
      const header = CacheControlHeader(
        maxAge: 300,
        noCache: true,
        mustRevalidate: true,
      );
      expect(header.toString(), contains('maxAge: 300'));
      expect(header.toString(), contains('noCache: true'));
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

class TestRequestHandlerWithCapture extends RequestInterceptorHandler {
  bool nextCalled = false;
  final void Function(RequestOptions) onNext;

  TestRequestHandlerWithCapture({required this.onNext});

  @override
  void next(RequestOptions options) {
    nextCalled = true;
    onNext(options);
  }
}

class TestResponseHandlerWithResolve extends ResponseInterceptorHandler {
  bool nextCalled = false;
  Response<dynamic>? resolvedResponse;

  @override
  void next(Response<dynamic> response) {
    nextCalled = true;
  }

  @override
  void resolve(Response<dynamic> response,
      [bool callFollowingResponseInterceptor = false]) {
    resolvedResponse = response;
  }
}
