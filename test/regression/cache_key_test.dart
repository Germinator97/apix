import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on how a cache key is built.
///
/// A cache key is the one place where being *almost* right is worse than being
/// wrong: two requests that should differ collapse onto one entry, and the
/// second caller silently receives the first one's body. Nothing raises.
void main() {
  ApiClient clientWith(ScriptedAdapter adapter, {CacheStorage? storage}) {
    return ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
      cacheConfig: CacheConfig(
        storage: storage,
        strategy: CacheStrategy.cacheFirst,
        defaultTtl: const Duration(minutes: 10),
      ),
    );
  }

  group('cache key — query parameters', () {
    test('two pages requested through queryParameters do not collide',
        () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'page': i}, 200),
      );
      final client = clientWith(adapter);

      final first =
          await client.get<dynamic>('/users', queryParameters: {'page': 1});
      final second =
          await client.get<dynamic>('/users', queryParameters: {'page': 2});

      expect(adapter.callCount, 2,
          reason: 'each page must reach the network on its own');
      expect(bodyOf(first)['page'], 0);
      expect(bodyOf(second)['page'], 1);
    });

    test('the same page asked twice is served from cache', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'page': i}, 200),
      );
      final client = clientWith(adapter);

      await client.get<dynamic>('/users', queryParameters: {'page': 1});
      final again =
          await client.get<dynamic>('/users', queryParameters: {'page': 1});

      expect(adapter.callCount, 1,
          reason: 'the second call must hit the cache');
      expect(again.isFromCache, isTrue);
      expect(again.isStale, isFalse);
    });

    test('B2 — two pages written inline in the path do not collide', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'call': i}, 200),
      );
      final client = clientWith(adapter);

      final first = await client.get<dynamic>('/users?page=1');
      final second = await client.get<dynamic>('/users?page=2');

      expect(adapter.callCount, 2,
          reason: 'page=2 must reach the network, not read page=1 back');
      expect(bodyOf(first)['call'], 0);
      expect(bodyOf(second)['call'], 1);
    });

    test('B2 — an inline query and the same one passed as a map share a key',
        () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'call': i}, 200),
      );
      final client = clientWith(adapter);

      await client.get<dynamic>('/users?page=1');
      await client.get<dynamic>('/users', queryParameters: {'page': 1});

      expect(adapter.callCount, 1,
          reason: 'the same request spelled two ways is the same request');
    });

    test('B2 — an inline query still caches on its own', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'call': i}, 200),
      );
      final client = clientWith(adapter);

      await client.get<dynamic>('/users?page=1');
      final again = await client.get<dynamic>('/users?page=1');

      expect(adapter.callCount, 1);
      expect(again.isFromCache, isTrue);
    });

    test('B2 — repeated parameters are not collapsed', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'call': i}, 200),
      );
      final client = clientWith(adapter);

      await client.get<dynamic>('/search?tag=a&tag=b');
      await client.get<dynamic>('/search?tag=a');

      expect(adapter.callCount, 2,
          reason: 'two tags and one tag are different requests');
    });

    test('B1 — a second identity is not served the first one\'s body',
        () async {
      final adapter = ScriptedAdapter(
        (options, i) =>
            jsonResponse({'me': options.headers['Authorization']}, 200),
      );
      final provider = StubTokenProvider(accessToken: 'token-A');
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        authConfig: AuthConfig(tokenProvider: provider),
        cacheConfig: CacheConfig(
          strategy: CacheStrategy.cacheFirst,
          defaultTtl: const Duration(minutes: 10),
        ),
      );

      final asA = await client.get<dynamic>('/me');
      expect(bodyOf(asA)['me'], 'Bearer token-A');

      // What a logout followed by a login as someone else looks like from
      // here: same device, same client, different token.
      provider.accessToken = 'token-B';
      final asB = await client.get<dynamic>('/me');

      expect(bodyOf(asB)['me'], 'Bearer token-B',
          reason: "user B must never be served user A's cached body");
      expect(adapter.callCount, 2,
          reason: 'the second identity must reach the network');
    });

    test('B1 — an anonymous request cannot read an authenticated entry',
        () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse(
            {'auth': options.headers['Authorization'] ?? 'none'}, 200),
      );
      final provider = StubTokenProvider(accessToken: 'token-A');
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        authConfig: AuthConfig(tokenProvider: provider),
        cacheConfig: CacheConfig(
          strategy: CacheStrategy.cacheFirst,
          defaultTtl: const Duration(minutes: 10),
        ),
      );

      await client.get<dynamic>('/thing');

      // Logged out: no header at all, so no fragment. That plain key must not
      // be the one the authenticated request wrote.
      provider.accessToken = null;
      final anonymous = await client.get<dynamic>('/thing');

      expect(bodyOf(anonymous)['auth'], 'none');
      expect(adapter.callCount, 2);
    });

    test('B1 — the same identity still hits the cache', () async {
      final adapter =
          ScriptedAdapter((options, i) => jsonResponse({'i': i}, 200));
      final provider = StubTokenProvider(accessToken: 'token-A');
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        authConfig: AuthConfig(tokenProvider: provider),
        cacheConfig: CacheConfig(
          strategy: CacheStrategy.cacheFirst,
          defaultTtl: const Duration(minutes: 10),
        ),
      );

      await client.get<dynamic>('/thing');
      final second = await client.get<dynamic>('/thing');

      // The other half of the fix: scoping must not disable caching outright.
      // A guard that only ever misses would pass the leak test above while
      // making the whole feature useless.
      expect(adapter.callCount, 1);
      expect(second.isFromCache, isTrue);
    });

    test('B1 — varyHeaders: [] restores the unscoped key', () async {
      final adapter =
          ScriptedAdapter((options, i) => jsonResponse({'i': i}, 200));
      final provider = StubTokenProvider(accessToken: 'token-A');
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        authConfig: AuthConfig(tokenProvider: provider),
        cacheConfig: CacheConfig(
          strategy: CacheStrategy.cacheFirst,
          defaultTtl: const Duration(minutes: 10),
          varyHeaders: const [],
        ),
      );

      await client.get<dynamic>('/thing');
      provider.accessToken = 'token-B';
      await client.get<dynamic>('/thing');

      expect(adapter.callCount, 1,
          reason: 'opting out must genuinely share entries across callers');
    });

    test('B1 — a custom header name is matched case-insensitively', () async {
      final adapter =
          ScriptedAdapter((options, i) => jsonResponse({'i': i}, 200));
      final provider = StubTokenProvider(accessToken: 'k1');
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        authConfig: AuthConfig(
          tokenProvider: provider,
          headerName: 'x-api-key',
          headerPrefix: '',
        ),
        cacheConfig: CacheConfig(
          strategy: CacheStrategy.cacheFirst,
          defaultTtl: const Duration(minutes: 10),
          varyHeaders: const ['X-API-Key'],
        ),
      );

      await client.get<dynamic>('/thing');
      provider.accessToken = 'k2';
      await client.get<dynamic>('/thing');

      expect(adapter.callCount, 2,
          reason: 'header names are case-insensitive; matching on the exact '
              'spelling would scope nothing while looking like it worked');
    });

    test('parameter order does not change the key', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'i': i}, 200),
      );
      final client = clientWith(adapter);

      await client.get<dynamic>('/search', queryParameters: {'a': 1, 'b': 2});
      await client.get<dynamic>('/search', queryParameters: {'b': 2, 'a': 1});

      expect(adapter.callCount, 1,
          reason: 'keys are sorted, so declaration order is irrelevant');
    });
  });
}
