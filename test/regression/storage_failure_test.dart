import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on what a *storage* failure is allowed to change.
///
/// A `CacheStorage` is supplied by the consumer and fails for reasons apix
/// knows nothing about. The rule these tests pin: once a response is in hand,
/// nothing the store does may change what the caller receives, and nothing may
/// cause the request to be sent again.
void main() {
  ApiClient clientWith(
    ScriptedAdapter adapter,
    CacheStorage storage, {
    CacheStrategy strategy = CacheStrategy.networkFirst,
    bool deduplicate = true,
  }) {
    return ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
      cacheConfig: CacheConfig(
        storage: storage,
        strategy: strategy,
        enableDeduplication: deduplicate,
      ),
    );
  }

  /// Answers with an incrementing counter, so "which response did the caller
  /// get" and "how many went out" are the same question read two ways.
  ScriptedAdapter countingAdapter() =>
      ScriptedAdapter((options, i) => jsonResponse({'n': i + 1}, 200));

  group('N1 — a failing cache write cannot replay the request', () {
    test('one network call, and the first response, when set() throws',
        () async {
      final adapter = countingAdapter();
      final storage = FailingCacheStorage();
      final client = clientWith(adapter, storage);

      final response = await client.get<dynamic>('/x');

      expect(
        adapter.callCount,
        1,
        reason: 'the write failure used to escape to onRequest, whose catch '
            'falls through to handler.next — sending the request again',
      );
      expect(
        bodyOf(response)['n'],
        1,
        reason: 'the caller must receive the response that was actually '
            'computed first, not the one from a replay it never asked for',
      );
      expect(storage.refused, ['set'],
          reason: 'the write really was attempted');
    });

    test('the defect needed deduplication, so pin the other branch too',
        () async {
      final adapter = countingAdapter();
      final client =
          clientWith(adapter, FailingCacheStorage(), deduplicate: false);

      final response = await client.get<dynamic>('/x');

      expect(adapter.callCount, 1);
      expect(bodyOf(response)['n'], 1);
    });

    test('a failing read does not replay a request that has already failed',
        () async {
      var attempts = 0;
      final adapter = ScriptedAdapter((options, i) {
        attempts++;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'offline',
        );
      });
      final client = clientWith(
        adapter,
        FailingCacheStorage(onSet: false, onGet: true),
      );

      await expectLater(
        client.get<dynamic>('/x'),
        throwsA(isA<ApiException>()),
      );

      expect(
        attempts,
        1,
        reason: 'the networkFirst fallback read is the second place a storage '
            'exception could escape into handler.next',
      );
    });

    test('a working store still caches — the guard must not swallow the write',
        () async {
      final adapter = countingAdapter();
      final storage = InMemoryCacheStorage();
      final client =
          clientWith(adapter, storage, strategy: CacheStrategy.cacheFirst);

      await client.get<dynamic>('/x');
      final second = await client.get<dynamic>('/x');

      expect(adapter.callCount, 1, reason: 'the second call must be a hit');
      expect(bodyOf(second)['n'], 1);
      expect(await storage.keys(), isNotEmpty);
    });
  });

  group('N6 — listing the keys is not a deletion', () {
    test('the offline fallback survives a call to getCacheKeys', () async {
      final storage = InMemoryCacheStorage();
      var offline = false;
      final adapter = ScriptedAdapter((options, i) {
        if (offline) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'offline',
          );
        }
        return jsonResponse({'v': 1}, 200);
      });
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        cacheConfig: CacheConfig(
          storage: storage,
          strategy: CacheStrategy.networkFirst,
          defaultTtl: const Duration(milliseconds: 20),
        ),
      );

      await client.get<dynamic>('/thing');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // The whole point: an operation that only *reads*, between the entry
      // expiring and the network dying.
      await client.cacheInterceptor!.getCacheKeys();

      offline = true;
      final served = await client.get<dynamic>('/thing');

      expect(
        bodyOf(served)['v'],
        1,
        reason: 'listing the keys used to sweep every expired entry, so asking '
            'what was cached destroyed the fallback that makes networkFirst '
            'useful — and a missing entry looks exactly like one that was '
            'never written',
      );
      expect(served.isStale, isTrue);
    });

    test('clearCache counts the expired entries it removes', () async {
      final storage = InMemoryCacheStorage();
      await storage.set(
        'GET:/a',
        CacheEntry.withTtl(
            data: '{}', statusCode: 200, ttl: const Duration(seconds: -1)),
      );
      await storage.set(
        'GET:/b',
        CacheEntry.withTtl(
            data: '{}', statusCode: 200, ttl: const Duration(minutes: 5)),
      );
      final interceptor =
          CacheInterceptor(config: CacheConfig(storage: storage));

      expect(await interceptor.clearCache(), 2,
          reason: 'it used to report 1, because keys() had already swept the '
              'expired one on its way past');
      expect(await storage.keys(), isEmpty);
    });

    test('evictExpired removes exactly the expired entries', () async {
      final storage = InMemoryCacheStorage();
      await storage.set(
        'GET:/stale',
        CacheEntry.withTtl(
            data: '{}', statusCode: 200, ttl: const Duration(seconds: -1)),
      );
      await storage.set(
        'GET:/fresh',
        CacheEntry.withTtl(
            data: '{}', statusCode: 200, ttl: const Duration(minutes: 5)),
      );
      final interceptor =
          CacheInterceptor(config: CacheConfig(storage: storage));

      expect(await interceptor.evictExpired(), 1);
      expect(await storage.keys(), ['GET:/fresh'],
          reason: 'the sweep is still available, under a name that says it '
              'deletes');
    });
  });

  group('N1 bis — the write path stays intact', () {
    test('a cacheFirst hit is still served from a working store', () async {
      final adapter = countingAdapter();
      final storage = InMemoryCacheStorage();
      final client =
          clientWith(adapter, storage, strategy: CacheStrategy.cacheFirst);

      await client.get<dynamic>('/x');
      final second = await client.get<dynamic>('/x');

      expect(adapter.callCount, 1, reason: 'the second call must be a hit');
      expect(bodyOf(second)['n'], 1);
      expect(await storage.keys(), isNotEmpty);
    });
  });
}
