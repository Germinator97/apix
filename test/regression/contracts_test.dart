import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on contracts the package promises and quietly broke.
void main() {
  group('M10 — RetryConfig honours the equals/hashCode contract', () {
    test('two equal configs share a hash code', () {
      const a = RetryConfig(retryStatusCodes: [500, 503]);
      final b = RetryConfig(retryStatusCodes: <int>[500, 503].toList());

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode),
          reason: 'the list was hashed by identity while == compared it '
              'element by element');
    });

    test('a Set collapses equal configs', () {
      const a = RetryConfig(retryStatusCodes: [500, 503]);
      final b = RetryConfig(retryStatusCodes: <int>[500, 503].toList());

      expect({a, b}, hasLength(1));
    });

    test('a Map finds a config stored under an equal key', () {
      const a = RetryConfig(retryStatusCodes: [500, 503]);
      final b = RetryConfig(retryStatusCodes: <int>[500, 503].toList());

      expect({a: 'x'}[b], 'x');
    });

    test('different status codes still differ', () {
      const a = RetryConfig(retryStatusCodes: [500, 503]);
      const b = RetryConfig(retryStatusCodes: [500, 504]);

      // The other direction: a hash that ignored the list entirely would pass
      // every test above.
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('order matters, as == says it does', () {
      const a = RetryConfig(retryStatusCodes: [500, 503]);
      const b = RetryConfig(retryStatusCodes: [503, 500]);

      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });

  group('M13 — invalidateUrl stops at the URL boundary', () {
    Future<(CacheInterceptor, CacheStorage, ScriptedAdapter)> primed() async {
      final storage = InMemoryCacheStorage();
      final adapter =
          ScriptedAdapter((options, i) => jsonResponse({'i': i}, 200));
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        cacheConfig: CacheConfig(
          storage: storage,
          strategy: CacheStrategy.cacheFirst,
          defaultTtl: const Duration(minutes: 10),
        ),
      );
      final interceptor =
          client.dio.interceptors.whereType<CacheInterceptor>().single;

      await client.get<dynamic>('/users');
      await client.get<dynamic>('/users?page=2');
      await client.get<dynamic>('/users-archived');
      await client.get<dynamic>('/users/123');

      return (interceptor, storage, adapter);
    }

    test('a sibling path survives', () async {
      final (interceptor, storage, _) = await primed();

      await interceptor.invalidateUrl('/users');
      final left = await storage.keys();

      expect(left.where((k) => k.contains('/users-archived')), hasLength(1),
          reason: 'a bare prefix match used to sweep this away');
      expect(left.where((k) => k.contains('/users/123')), hasLength(1),
          reason: 'a sub-path is a different URL; invalidatePath is for those');
    });

    test('every query variant of the exact URL goes', () async {
      final (interceptor, storage, _) = await primed();

      await interceptor.invalidateUrl('/users');
      final left = await storage.keys();

      // The direction that must not break while tightening the match.
      expect(left.where((k) => k.contains('/users?')), isEmpty);
      expect(
        left.where((k) => RegExp(r'/users(\||$)').hasMatch(k)),
        isEmpty,
      );
    });

    test('invalidatePath still clears the whole subtree', () async {
      final (interceptor, storage, _) = await primed();

      await interceptor.invalidatePath('/users');

      expect(await storage.keys(), isEmpty,
          reason: 'the broad sweep is still available, under its own name');
    });
  });

  group('M14 — a reused RequestOptions is observed on every execution', () {
    test('two executions produce two log entries', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'message': 'boom'}, 500),
      );
      final logged = <LogEntry>[];
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        loggerConfig: LoggerConfig(
          level: LogLevel.error,
          logHandler: logged.add,
        ),
      );

      final options = RequestOptions(
        path: '/thing',
        baseUrl: 'https://api.test',
        method: 'GET',
      );

      for (var i = 0; i < 2; i++) {
        try {
          await client.dio.fetch<dynamic>(options);
        } catch (_) {
          // expected
        }
      }

      expect(logged, hasLength(2),
          reason: 'the marks live on extra, which outlives one execution; the '
              'second failure used to be observed by nobody');
    });

    test('a retry storm is still ONE event, not one per attempt', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'message': 'boom'}, 500),
      );
      final logged = <LogEntry>[];
      final attempts = <RetryAttempt>[];
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        retryConfig: const RetryConfig(maxAttempts: 3, baseDelayMs: 1),
        onRetry: attempts.add,
        loggerConfig: LoggerConfig(
          level: LogLevel.error,
          logHandler: logged.add,
        ),
      );

      await expectLater(
        client.get<dynamic>('/thing'),
        throwsA(isA<ServerException>()),
      );

      // The contract the marker exists for, and which resetting on every
      // onRequest would have destroyed: one logical request, one event. The
      // attempts are what onRetry reports.
      expect(adapter.callCount, 4,
          reason: 'initial request plus three retries');
      expect(attempts, hasLength(3));
      expect(logged, hasLength(1),
          reason: 'a three-try storm must not file three failures');
    });

    test('an auth replay is still ONE event', () async {
      final adapter = ScriptedAdapter((options, i) {
        if (options.path.contains('refresh')) {
          return jsonResponse({'access_token': 'fresh'}, 200);
        }
        return i == 0
            ? jsonResponse({'message': 'expired'}, 401)
            : jsonResponse({'message': 'still no'}, 401);
      });
      final logged = <LogEntry>[];
      final provider = StubTokenProvider();
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        authConfig: AuthConfig(
          tokenProvider: provider,
          refreshEndpoint: '/auth/refresh',
          onTokenRefreshed: (response) async {
            await provider.saveTokens('fresh', 'ref');
          },
        ),
        loggerConfig: LoggerConfig(
          level: LogLevel.error,
          logHandler: logged.add,
        ),
      );

      await expectLater(
        client.get<dynamic>('/me'),
        throwsA(isA<UnauthorizedException>()),
      );

      final forMe =
          logged.where((entry) => entry.url?.contains('/me') ?? false);
      expect(forMe, hasLength(1),
          reason: 'the replayed attempt must not double the report');
    });
  });
}
