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
}
