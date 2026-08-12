import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on what a cache hit gives back.
///
/// Both defects here need **two** consecutive requests to appear: the first
/// call goes to the network and is correct, the second reads storage and is
/// not. A single round trip shows nothing, which is why they survived.
void main() {
  ApiClient clientWith(
    ScriptedAdapter adapter, {
    required CacheStrategy strategy,
    Duration ttl = const Duration(minutes: 10),
  }) {
    return ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
      cacheConfig: CacheConfig(strategy: strategy, defaultTtl: ttl),
    );
  }

  group('M7 — a cache hit returns the type the network returned', () {
    test('a text/plain numeric body stays a String', () async {
      final adapter =
          ScriptedAdapter((options, i) => textResponse('12345', 200));
      final client = clientWith(adapter, strategy: CacheStrategy.cacheFirst);

      final live = await client.get<dynamic>('/count');
      final cached = await client.get<dynamic>('/count');

      expect(live.data, isA<String>());
      expect(cached.data, isA<String>(),
          reason: 'jsonDecode used to turn "12345" into the int 12345');
      expect(cached.data, live.data);
      expect(adapter.callCount, 1);
    });

    test('a text body that looks like JSON is not re-parsed', () async {
      final adapter = ScriptedAdapter(
        (options, i) => textResponse('{"not":"parsed"}', 200),
      );
      final client = clientWith(adapter, strategy: CacheStrategy.cacheFirst);

      final live = await client.get<dynamic>('/raw');
      final cached = await client.get<dynamic>('/raw');

      expect(live.data, isA<String>());
      expect(cached.data, isA<String>());
      expect(cached.data, live.data);
    });

    test('a binary download stays bytes', () async {
      final adapter = ScriptedAdapter(
        (options, i) => ResponseBody.fromBytes([1, 2, 3, 4], 200,
            headers: {
              Headers.contentTypeHeader: ['application/octet-stream'],
            }),
      );
      final client = clientWith(adapter, strategy: CacheStrategy.cacheFirst);
      final options = Options(responseType: ResponseType.bytes);

      final live = await client.get<dynamic>('/file', options: options);
      final cached = await client.get<dynamic>('/file', options: options);

      expect(live.data, isA<Uint8List>());
      expect(cached.data, isA<Uint8List>(),
          reason: 'a cached download used to come back as List<dynamic>, so '
              'any cast at the call site threw on the second request');
      expect(cached.data, equals(live.data));
    });

    test('a JSON object still round-trips as a map', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'id': 1, 'name': 'John'}, 200),
      );
      final client = clientWith(adapter, strategy: CacheStrategy.cacheFirst);

      await client.get<dynamic>('/user');
      final cached = await client.get<dynamic>('/user');

      // The direction that must not regress while fixing the others.
      expect(cached.data, isA<Map<String, dynamic>>());
      expect(bodyOf(cached)['name'], 'John');
    });

    test('a JSON list still round-trips as a list', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse([1, 2, 3], 200),
      );
      final client = clientWith(adapter, strategy: CacheStrategy.cacheFirst);

      await client.get<dynamic>('/ids');
      final cached = await client.get<dynamic>('/ids');

      expect(cached.data, isA<List<dynamic>>());
      expect(cached.data, equals([1, 2, 3]));
    });
  });

  group('M6 — a 304 confirms the entry rather than ageing it', () {
    /// Serves a body once, then only 304s — the shape of a real conditional
    /// request against an unchanged resource.
    ScriptedAdapter conditional() => ScriptedAdapter((options, i) {
          if (i == 0) {
            return jsonResponse({'v': 1}, 200,
                headers: {
                  'etag': ['"abc"'],
                });
          }
          return ResponseBody.fromString('', 304, headers: {
            'etag': ['"abc"'],
          });
        });

    test('the revalidated body is served as fresh, not stale', () async {
      final adapter = conditional();
      final client = clientWith(
        adapter,
        strategy: CacheStrategy.httpCacheAware,
        ttl: const Duration(milliseconds: 20),
      );

      await client.get<dynamic>('/thing');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final revalidated = await client.get<dynamic>('/thing');

      expect(bodyOf(revalidated)['v'], 1);
      expect(revalidated.isFromCache, isTrue);
      expect(revalidated.isStale, isFalse,
          reason: 'the server just said the body is current; reporting it '
              'stale contradicts the answer we received');
    });

    test('the entry stops being revalidated on every later request', () async {
      final adapter = conditional();
      final client = clientWith(
        adapter,
        strategy: CacheStrategy.httpCacheAware,
        ttl: const Duration(milliseconds: 20),
      );

      await client.get<dynamic>('/thing');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await client.get<dynamic>('/thing'); // revalidates -> 304
      final afterRevalidation = adapter.callCount;

      await client.get<dynamic>('/thing');

      expect(adapter.callCount, afterRevalidation,
          reason: 'httpCacheAware degenerated into "always revalidate" '
              'because a 304 never restarted the TTL');
    });

    test('the conditional request carries the stored ETag', () async {
      final adapter = conditional();
      final client = clientWith(
        adapter,
        strategy: CacheStrategy.httpCacheAware,
        ttl: const Duration(milliseconds: 20),
      );

      await client.get<dynamic>('/thing');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await client.get<dynamic>('/thing');

      expect(adapter.seen.last.headers['If-None-Match'], '"abc"');
    });

    test('a 304 with nothing stored still surfaces as a failure', () async {
      final adapter = ScriptedAdapter(
        (options, i) => ResponseBody.fromString('', 304),
      );
      final client =
          clientWith(adapter, strategy: CacheStrategy.httpCacheAware);

      // The other direction: inventing a body we never stored would be worse
      // than failing.
      await expectLater(
        client.get<dynamic>('/thing'),
        throwsA(isA<ApiException>()),
      );
    });

    test('a genuine network failure still falls back to a stale entry',
        () async {
      final adapter = ScriptedAdapter((options, i) {
        if (i == 0) return jsonResponse({'v': 1}, 200);
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'offline',
        );
      });
      final client = clientWith(
        adapter,
        strategy: CacheStrategy.httpCacheAware,
        ttl: const Duration(milliseconds: 20),
      );

      await client.get<dynamic>('/thing');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final offline = await client.get<dynamic>('/thing');

      // Handling 304 first must not have swallowed the offline fallback.
      expect(bodyOf(offline)['v'], 1);
      expect(offline.isStale, isTrue,
          reason: 'this body really is past its TTL and unconfirmed');
    });
  });
}
