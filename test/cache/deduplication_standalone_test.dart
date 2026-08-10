import 'dart:async';
import 'dart:convert';

import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts how many requests actually reached the wire, and holds each one open
/// until [release] so concurrency is deterministic rather than timing-based.
class _CountingAdapter implements HttpClientAdapter {
  int hits = 0;
  final _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    hits++;
    await _gate.future;
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'value': 'ok'})),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('standalone deduplication', () {
    // The point of the whole feature: deduplication without ever installing a
    // store. Before this existed, the only way to get here was a CacheStorage
    // whose writes were deliberately dropped.
    test('collapses concurrent GETs with no cacheConfig at all', () async {
      final adapter = _CountingAdapter();
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        deduplicationConfig: const DeduplicationConfig(),
        httpClientAdapter: adapter,
      );

      final inFlight = [
        client.get<dynamic>('/profile'),
        client.get<dynamic>('/profile'),
        client.get<dynamic>('/profile'),
      ];
      await Future<void>.delayed(Duration.zero);
      adapter.release();
      await Future.wait(inFlight);

      expect(adapter.hits, equals(1));
    });

    // A deduplicator that collapses too much is invisible: it produces an
    // absence, and an absence looks like nothing happened. So assert what must
    // still get through, not only what is merged.
    test('lets different URLs through untouched', () async {
      final adapter = _CountingAdapter()..release();
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        deduplicationConfig: const DeduplicationConfig(),
        httpClientAdapter: adapter,
      );

      await Future.wait([
        client.get<dynamic>('/a'),
        client.get<dynamic>('/b'),
        client.get<dynamic>('/c'),
      ]);

      expect(adapter.hits, equals(3));
    });

    test('lets sequential identical GETs through — only concurrent ones merge',
        () async {
      final adapter = _CountingAdapter()..release();
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        deduplicationConfig: const DeduplicationConfig(),
        httpClientAdapter: adapter,
      );

      await client.get<dynamic>('/profile');
      await client.get<dynamic>('/profile');

      expect(
        adapter.hits,
        equals(2),
        reason: 'deduplication is about concurrency, not caching — a later '
            'request must still hit the network',
      );
    });

    test('leaves non-listed methods alone', () async {
      final adapter = _CountingAdapter()..release();
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        deduplicationConfig: const DeduplicationConfig(),
        httpClientAdapter: adapter,
      );

      await Future.wait([
        client.post<dynamic>('/pay', data: {'amount': 1000}),
        client.post<dynamic>('/pay', data: {'amount': 1000}),
      ]);

      expect(
        adapter.hits,
        equals(2),
        reason: 'collapsing two identical POSTs would drop a payment the '
            'caller meant to send twice',
      );
    });

    test('a disabled config deduplicates nothing', () async {
      final adapter = _CountingAdapter()..release();
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        deduplicationConfig: DeduplicationConfig.disabled(),
        httpClientAdapter: adapter,
      );

      await Future.wait([
        client.get<dynamic>('/profile'),
        client.get<dynamic>('/profile'),
      ]);

      expect(adapter.hits, equals(2));
    });

    test('errors reach every waiter of a collapsed request', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        deduplicationConfig: const DeduplicationConfig(),
        httpClientAdapter: _FailingAdapter(),
      );

      final results = await Future.wait([
        client.get<dynamic>('/boom').then<Object?>((r) => r).catchError(
              (Object e) => e,
            ),
        client.get<dynamic>('/boom').then<Object?>((r) => r).catchError(
              (Object e) => e,
            ),
      ]);

      expect(results[0], isA<ServerException>());
      expect(
        results[1],
        isA<ServerException>(),
        reason: 'a waiter must not be left hanging, nor silently succeed, '
            'because its request was merged into a failing one',
      );
    });
  });

  group('networkOnly never writes', () {
    Future<List<String>> keysAfterGet({
      required CacheStrategy strategy,
      required bool enableDeduplication,
    }) async {
      final storage = InMemoryCacheStorage();
      final cacheConfig = CacheConfig(
        storage: storage,
        strategy: strategy,
        enableDeduplication: enableDeduplication,
      );
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        cacheConfig: cacheConfig,
        httpClientAdapter: _CountingAdapter()..release(),
      );

      await client.get<dynamic>('/balance');
      return storage.keys();
    }

    // Two write sites, not one: onResponse and the deduplicated path. A guard
    // on only the first would leave balances flowing into a store on exactly
    // the path a consumer enabling deduplication would take.
    test('writes nothing on the plain path', () async {
      expect(
        await keysAfterGet(
          strategy: CacheStrategy.networkOnly,
          enableDeduplication: false,
        ),
        isEmpty,
      );
    });

    test('writes nothing on the deduplicated path', () async {
      expect(
        await keysAfterGet(
          strategy: CacheStrategy.networkOnly,
          enableDeduplication: true,
        ),
        isEmpty,
        reason: 'this is the site the integration report missed — a guard on '
            'onResponse alone still leaks here',
      );
    });

    // The other half: a guard that cuts too much would disable caching for
    // everyone, and nothing would raise.
    test('networkFirst still writes on the plain path', () async {
      expect(
        await keysAfterGet(
          strategy: CacheStrategy.networkFirst,
          enableDeduplication: false,
        ),
        isNotEmpty,
      );
    });

    test('networkFirst still writes on the deduplicated path', () async {
      expect(
        await keysAfterGet(
          strategy: CacheStrategy.networkFirst,
          enableDeduplication: true,
        ),
        isNotEmpty,
      );
    });
  });
}

/// Always answers 500, so the failure path of a collapsed request can be
/// observed by every waiter.
class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'message': 'boom'})),
      500,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
