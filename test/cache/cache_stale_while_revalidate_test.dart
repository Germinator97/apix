import 'dart:convert';
import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the 3.0.0 cache contract:
///
/// - `cacheFirst` serves the cache **immediately**, stale included, and
///   revalidates behind — it never blocks on the network when an entry exists;
/// - the TTL is enforced by the interceptor, not by the storage;
/// - every cached body says whether it is stale.
///
/// The tests measure **how many times the server was hit** and **what the
/// caller received**, never the internals — a rewrite of the strategy that
/// keeps both is free to happen.
void main() {
  late _CountingAdapter adapter;
  late InMemoryCacheStorage storage;

  /// Builds a client whose only cache strategy is [strategy].
  ApiClient clientFor(CacheStrategy strategy, {Duration? ttl}) {
    return ApiClientFactory.create(
      baseUrl: 'https://cache.test.local',
      cacheConfig: CacheConfig(
        storage: storage,
        strategy: strategy,
        defaultTtl: ttl ?? const Duration(minutes: 5),
      ),
      httpClientAdapter: adapter,
    );
  }

  /// Seeds the cache for `GET /items` with an entry that is already expired.
  Future<void> seedStale() async {
    await storage.set(
      'GET:https://cache.test.local/items',
      CacheEntry(
        data: jsonEncode({'source': 'cache'}),
        statusCode: 200,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );
  }

  Future<void> seedFresh() async {
    await storage.set(
      'GET:https://cache.test.local/items',
      CacheEntry.withTtl(
        data: jsonEncode({'source': 'cache'}),
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      ),
    );
  }

  setUp(() {
    adapter = _CountingAdapter();
    storage = InMemoryCacheStorage();
  });

  group('cacheFirst serves the cache and revalidates behind', () {
    test('a fresh entry is served without touching the network', () async {
      await seedFresh();
      final client = clientFor(CacheStrategy.cacheFirst);

      final response = await client.get<dynamic>('/items');

      expect(response.isFromCache, isTrue);
      expect(response.isStale, isFalse);
      expect(adapter.hits, 0, reason: 'a fresh entry must cost nothing');
    });

    test('a stale entry is served immediately, flagged, and refreshed',
        () async {
      await seedStale();
      final client = clientFor(CacheStrategy.cacheFirst);

      final response = await client.get<dynamic>('/items');

      // The caller got the stale body without waiting.
      expect(response.isFromCache, isTrue);
      expect(
        response.isStale,
        isTrue,
        reason: 'serving expired data without saying so is the whole risk',
      );
      expect((response.data as Map)['source'], 'cache');

      // ...and the refresh lands behind it.
      CacheEntry? entry;
      await _until('the cache entry to be renewed', () async {
        entry = await storage.get('GET:https://cache.test.local/items');
        return entry != null && entry!.isValid;
      });
      expect((jsonDecode(entry!.data) as Map)['source'], 'network');
      expect(adapter.hits, 1);
    });

    test('serving stale costs exactly one request, like blocking did',
        () async {
      // The behaviour change is that the caller stops waiting — NOT that apix
      // starts talking to the network more. Same volume as the pre-3.0.0
      // blocking refetch.
      await seedStale();
      final client = clientFor(CacheStrategy.cacheFirst);

      await client.get<dynamic>('/items');
      await _until('the revalidation to complete', () async {
        final e = await storage.get('GET:https://cache.test.local/items');
        return e != null && e.isValid;
      });

      expect(adapter.hits, 1);
    });

    test('a failing revalidation keeps the stale entry and never throws',
        () async {
      await seedStale();
      adapter.failing = true;
      final client = clientFor(CacheStrategy.cacheFirst);

      final response = await client.get<dynamic>('/items');
      expect(response.isStale, isTrue);

      await _until('the failing revalidation to be attempted',
          () async => adapter.hits >= 1);
      // Let the failure settle: an unhandled async error would surface here.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The entry survives for the next attempt.
      final kept = await storage.get('GET:https://cache.test.local/items');
      expect(kept, isNotNull);
      expect((jsonDecode(kept!.data) as Map)['source'], 'cache');
    });

    test('no cache at all still goes to the network', () async {
      final client = clientFor(CacheStrategy.cacheFirst);

      final response = await client.get<dynamic>('/items');

      expect(response.isFromCache, isFalse);
      expect(adapter.hits, 1);
    });
  });

  group('the TTL is enforced by the interceptor', () {
    test('cacheOnly refuses an expired entry instead of serving it', () async {
      await seedStale();
      final client = clientFor(CacheStrategy.cacheOnly);

      // Storage hands the stale entry over — the interceptor is what rejects
      // it. Before 3.0.0 this guarantee lived in InMemoryCacheStorage, so any
      // third-party backend that forgot to filter silently disabled the TTL.
      expect(
        await storage.get('GET:https://cache.test.local/items'),
        isNotNull,
      );

      await expectLater(
        client.get<dynamic>('/items'),
        throwsA(isA<ApiException>()),
      );
      expect(adapter.hits, 0);
    });

    test('cacheOnly serves a valid entry', () async {
      await seedFresh();
      final client = clientFor(CacheStrategy.cacheOnly);

      final response = await client.get<dynamic>('/items');

      expect(response.isFromCache, isTrue);
      expect(response.isStale, isFalse);
    });
  });

  group('offline fallback is served but flagged', () {
    test('networkFirst falls back to a stale entry and marks it', () async {
      await seedStale();
      adapter.failing = true;
      final client = clientFor(CacheStrategy.networkFirst);

      final response = await client.get<dynamic>('/items');

      expect(response.isFromCache, isTrue);
      expect(
        response.isStale,
        isTrue,
        reason: 'offline data is worth serving, not worth passing off as fresh',
      );
    });

    test('networkFirst fallback on a fresh entry is not flagged stale',
        () async {
      await seedFresh();
      adapter.failing = true;
      final client = clientFor(CacheStrategy.networkFirst);

      final response = await client.get<dynamic>('/items');

      expect(response.isFromCache, isTrue);
      expect(response.isStale, isFalse);
    });
  });
}

/// Polls [condition] until it holds, so background work can be observed
/// without sleeping for a fixed duration.
///
/// Never poll the adapter hit count to conclude the refresh *landed*: the
/// counter increments when the request is issued, so it goes green while the
/// cache write is still in flight.
Future<void> _until(String what, Future<bool> Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('timed out waiting for: $what');
}

/// Answers `{"source":"network"}` and counts calls; can be flipped to fail.
class _CountingAdapter implements HttpClientAdapter {
  final HttpClientAdapter _fallback = IOHttpClientAdapter();

  int hits = 0;
  bool failing = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    hits++;
    if (failing) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'source': 'network'})),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) => _fallback.close(force: force);
}
