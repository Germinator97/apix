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
