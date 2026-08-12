import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on [CacheConfig.onCacheHit].
///
/// A cache hit resolves from `onRequest`, so it never reaches the logger, the
/// metrics or the tracing interceptor — measured, and deliberate for tracing.
/// The consequence nobody had written down is that the *fastest* requests are
/// absent from every dashboard and the cache's own hit rate cannot be read from
/// the observability the package ships. This callback is the answer, so it has
/// to fire on every path that answers from storage — all of them, not the two
/// that were easy to remember.
void main() {
  ({ApiClient client, List<CacheHit> hits}) clientWith(
    ScriptedAdapter adapter, {
    required CacheStrategy strategy,
    Duration ttl = const Duration(minutes: 10),
  }) {
    final hits = <CacheHit>[];
    final client = ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
      cacheConfig: CacheConfig(
        strategy: strategy,
        defaultTtl: ttl,
        onCacheHit: hits.add,
      ),
    );
    return (client: client, hits: hits);
  }

  ScriptedAdapter ok() =>
      ScriptedAdapter((options, i) => jsonResponse({'i': i}, 200));

  group('N7 — every path that answers from storage reports it', () {
    test('a fresh cacheFirst hit', () async {
      final wired = clientWith(ok(), strategy: CacheStrategy.cacheFirst);

      await wired.client.get<dynamic>('/thing');
      expect(wired.hits, isEmpty, reason: 'the first call is a network call');

      await wired.client.get<dynamic>('/thing');

      expect(wired.hits, hasLength(1));
      expect(wired.hits.single.isStale, isFalse);
      expect(wired.hits.single.method, 'GET');
      expect(wired.hits.single.uri.path, '/thing');
      expect(wired.hits.single.statusCode, 200);
      expect(wired.hits.single.key, contains('/thing'));
    });

    test('a stale cacheFirst hit is reported as stale', () async {
      final wired = clientWith(
        ok(),
        strategy: CacheStrategy.cacheFirst,
        ttl: const Duration(milliseconds: 20),
      );

      await wired.client.get<dynamic>('/thing');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await wired.client.get<dynamic>('/thing');

      expect(wired.hits.single.isStale, isTrue,
          reason: 'a hit rate that counts stale and fresh together measures '
              'two different things');
    });

    test('a cacheOnly hit', () async {
      final wired = clientWith(ok(), strategy: CacheStrategy.cacheFirst);
      await wired.client.get<dynamic>('/thing');
      wired.hits.clear();

      await wired.client.get<dynamic>(
        '/thing',
        options: Options(extra: {'cacheStrategy': CacheStrategy.cacheOnly}),
      );

      expect(wired.hits, hasLength(1));
    });

    test('an offline fallback under networkFirst', () async {
      var offline = false;
      final adapter = ScriptedAdapter((options, i) {
        if (offline) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'offline',
          );
        }
        return jsonResponse({'i': i}, 200);
      });
      final wired = clientWith(adapter, strategy: CacheStrategy.networkFirst);

      await wired.client.get<dynamic>('/thing');
      wired.hits.clear();
      offline = true;
      await wired.client.get<dynamic>('/thing');

      expect(wired.hits, hasLength(1),
          reason: 'the fallback is the moment a consumer most wants to know '
              'the body did not come from the network');
      expect(wired.hits.single.isStale, isFalse,
          reason: 'this entry is still within its TTL');
    });

    test('a 304 confirming the stored body', () async {
      final adapter = ScriptedAdapter((options, i) {
        if (i == 0) {
          return jsonResponse({'v': 1}, 200,
              headers: {
                'etag': ['"abc"'],
              });
        }
        return jsonResponse(null, 304);
      });
      final wired = clientWith(
        adapter,
        strategy: CacheStrategy.httpCacheAware,
        ttl: const Duration(milliseconds: 20),
      );

      await wired.client.get<dynamic>('/thing');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      wired.hits.clear();
      await wired.client.get<dynamic>('/thing');

      expect(wired.hits, hasLength(1));
      expect(wired.hits.single.isStale, isFalse,
          reason: 'the server has just confirmed this body is current');
    });

    test('a network response is never reported as a hit', () async {
      final wired = clientWith(ok(), strategy: CacheStrategy.networkFirst);

      await wired.client.get<dynamic>('/a');
      await wired.client.get<dynamic>('/b');

      expect(wired.hits, isEmpty);
    });

    test('a handler that throws does not fail the request', () async {
      final adapter = ok();
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        cacheConfig: CacheConfig(
          strategy: CacheStrategy.cacheFirst,
          onCacheHit: (_) => throw StateError('consumer bug'),
        ),
      );

      await client.get<dynamic>('/thing');
      final second = await client.get<dynamic>('/thing');

      expect(second.isFromCache, isTrue,
          reason: 'observability must never break the path it observes');
      expect(bodyOf(second)['i'], 0);
    });
  });
}
