import 'dart:convert';

import 'package:apix/apix.dart';
import 'package:apix/src/http/retry_after.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// A header sent twice must never cost the caller its typed exception.
///
/// dio's `Headers.value` throws as soon as a field carries two values, and
/// five sites in apix called it. Repeats are ordinary: a gateway and the
/// application behind it both set `Retry-After`, two layers each add their
/// own `Cache-Control`. The throw escaped whichever interceptor was reading,
/// and the caller received a raw `DioException` where the documentation
/// promises an `ApiException` — on a `429`, the one status whose header is
/// the whole point.
void main() {
  ResponseBody json(
    Object body,
    int status, {
    Map<String, List<String>> headers = const {},
  }) {
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
      ...headers,
    });
  }

  ApiClient clientFor(ScriptedAdapter adapter, {bool strict = false}) =>
      ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        strictContentType: strict,
      );

  group('Retry-After sent twice', () {
    test('a 429 stays a TooManyRequestsException, with the longest delay',
        () async {
      final client = clientFor(ScriptedAdapter(
        (options, i) => json(
          {'message': 'Slow down', 'code': 'RATE_LIMITED'},
          429,
          headers: {
            'retry-after': ['30', '60'],
          },
        ),
      ));

      await expectLater(
        client.get<dynamic>('/items'),
        throwsA(isA<TooManyRequestsException>()
            .having(
                (e) => e.retryAfter, 'retryAfter', const Duration(seconds: 60))
            .having((e) => e.message, 'message', 'Slow down')
            .having((e) => e.code, 'code', 'RATE_LIMITED')),
      );
    });

    test('the retry waits the longest delay too', () async {
      final delays = <Duration>[];
      final adapter = ScriptedAdapter((options, i) => i == 0
          ? textResponse('busy', 503, headers: {
              'retry-after': ['0', '3600'],
            })
          : json({'ok': true}, 200));
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        // A long exponential base, so a header that went unread would show.
        retryConfig: const RetryConfig(
          maxAttempts: 2,
          retryStatusCodes: [503],
          baseDelayMs: 10000,
          maxDelayMs: 30,
        ),
        onRetry: (attempt) => delays.add(attempt.delay),
      );

      final response = await client.get<dynamic>('/items');

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
      expect(delays, [const Duration(milliseconds: 30)],
          reason: 'one hour clamped to maxDelayMs — the longer of the two '
              'values; taking the first would have waited nothing');
    });

    test('values that do not parse are skipped, never fatal', () {
      Headers of(List<String> values) =>
          Headers.fromMap({'Retry-After': values});

      expect(retryAfterFrom(of(['soon', '5'])), const Duration(seconds: 5));
      expect(retryAfterFrom(of(['soon'])), isNull);
      expect(retryAfterFrom(of(['7'])), const Duration(seconds: 7));
      expect(retryAfterFrom(Headers()), isNull);
      expect(retryAfterFrom(null), isNull);
    });

    test('an HTTP-date is not split on its comma', () {
      final now = DateTime.utc(2026, 10, 21, 7, 27);
      final headers = Headers.fromMap({
        'retry-after': ['Wed, 21 Oct 2026 07:28:00 GMT'],
      });

      expect(retryAfterFrom(headers, now: now), const Duration(minutes: 1));
    });
  });

  group('Content-Type sent twice', () {
    test('the first line decides, as it does for dio', () async {
      final client = clientFor(
        ScriptedAdapter((options, i) => ResponseBody.fromString(
              jsonEncode({'id': 7}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json', 'text/html'],
              },
            )),
        strict: true,
      );

      final id = await client.getAndDecode('/items/7', (j) => j['id'] as int);

      expect(id, 7);
    });

    test('a first line that is not JSON is refused by type, not by a crash',
        () async {
      final client = clientFor(
        ScriptedAdapter((options, i) => ResponseBody.fromString(
              '<html>portal</html>',
              200,
              headers: {
                Headers.contentTypeHeader: ['text/html', 'application/json'],
              },
            )),
        strict: true,
      );

      await expectLater(
        client.getAndDecode('/items/7', (j) => j),
        throwsA(isA<UnexpectedContentTypeException>().having(
            (e) => e.actualContentType, 'actualContentType', 'text/html')),
      );
    });
  });

  group('Cache-Control and ETag sent twice', () {
    ApiClient cachingClient(ScriptedAdapter adapter) => ApiClientFactory.create(
          baseUrl: 'https://api.test',
          httpClientAdapter: adapter,
          cacheConfig: CacheConfig(
            strategy: CacheStrategy.httpCacheAware,
            defaultTtl: Duration.zero,
          ),
        );

    test('the lines combine: max-age read from one of them', () async {
      final adapter = ScriptedAdapter((options, i) => json(
            {'n': i},
            200,
            headers: {
              'cache-control': ['private', 'max-age=60'],
            },
          ));
      final client = cachingClient(adapter);

      await client.get<dynamic>('/thing');
      final second = await client.get<dynamic>('/thing');

      expect(adapter.callCount, 1,
          reason: 'max-age=60 lives on the second line; read as one field '
              'it keeps the entry fresh for a minute');
      expect(second.isFromCache, isTrue);
    });

    test('the first ETag is the one sent back', () async {
      final adapter = ScriptedAdapter((options, i) {
        if (i == 0) {
          return json({'v': 1}, 200,
              headers: {
                'etag': ['"v1"', '"v2"'],
                'cache-control': ['no-cache'],
              });
        }
        return ResponseBody.fromString('', 304);
      });
      final client = cachingClient(adapter);

      await client.get<dynamic>('/thing');
      await client.get<dynamic>('/thing');

      expect(adapter.callCount, 2);
      expect(adapter.seen.last.headers['If-None-Match'], '"v1"');
    });
  });
}
