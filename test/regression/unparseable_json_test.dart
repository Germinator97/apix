import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// A body that claims JSON and is not must never cost the response its status.
///
/// dio decodes before any interceptor runs, and a decoding failure used to
/// leave with no `response` at all. Measured on both dio bounds under the
/// default `ResponseType.json`: a truncated `400` became
/// `ApiException('Unknown error')` with no status, a `401` answered in plain
/// text under `application/json` stopped refreshing the token, and a
/// truncated `200` was not the `ParsingException` its own documentation
/// promises for "truncated JSON".
void main() {
  ResponseBody claimingJson(
    String body,
    int status, {
    String contentType = 'application/json',
  }) {
    return ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [contentType],
    });
  }

  /// A body delivered chunk by chunk, with the length announced — the shape
  /// under which recent dio decodes JSON while it streams.
  ResponseBody chunked(List<String> chunks, int status) {
    final bytes = chunks.map((c) => Uint8List.fromList(utf8.encode(c)));
    final length = bytes.fold<int>(0, (sum, b) => sum + b.length);
    return ResponseBody(Stream.fromIterable(bytes), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
      Headers.contentLengthHeader: ['$length'],
    });
  }

  ApiClient clientFor(
    ScriptedAdapter adapter, {
    AuthConfig? authConfig,
    RetryConfig? retryConfig,
    CacheConfig? cacheConfig,
    ErrorTrackingConfig? errorTrackingConfig,
  }) {
    return ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
      authConfig: authConfig,
      retryConfig: retryConfig,
      cacheConfig: cacheConfig,
      errorTrackingConfig: errorTrackingConfig,
    );
  }

  group('an error response keeps its status', () {
    test('a 400 whose JSON is truncated is a ClientException', () async {
      final client = clientFor(
          ScriptedAdapter((o, i) => claimingJson('{"message":"x', 400)));

      await expectLater(
        client.get<dynamic>('/items'),
        throwsA(isA<ClientException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', 'HTTP 400')
            .having((e) => e.responseBody, 'responseBody', '{"message":"x')),
      );
    });

    test('a 401 answered in plain text under application/json still refreshes',
        () async {
      final provider = StubTokenProvider();
      final adapter = ScriptedAdapter((options, i) {
        if (options.path.contains('refresh')) {
          return jsonResponse({'access_token': 'fresh'}, 200);
        }
        return i == 0
            ? claimingJson('Unauthorized', 401)
            : jsonResponse({'id': 1}, 200);
      });
      final client = clientFor(
        adapter,
        authConfig: AuthConfig(
          tokenProvider: provider,
          refreshEndpoint: '/auth/refresh',
          onTokenRefreshed: (response) async {
            await provider.saveTokens('fresh', 'ref');
          },
        ),
      );

      final response = await client.get<dynamic>('/me');

      expect(response.statusCode, 200);
      expect(provider.saved, isNotEmpty,
          reason: 'the refresh only runs when the 401 is still a 401');
    });

    test('a 503 whose body does not parse is retried like any 503', () async {
      final adapter = ScriptedAdapter((o, i) => i == 0
          ? claimingJson('<html>maintenance</html>', 503)
          : jsonResponse({'ok': true}, 200));
      final client = clientFor(
        adapter,
        retryConfig: const RetryConfig(
          maxAttempts: 2,
          retryStatusCodes: [503],
          baseDelayMs: 1,
          maxDelayMs: 1,
          jitter: 0,
        ),
      );

      final response = await client.get<dynamic>('/items');

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
    });

    test('a body that fails half-way through a stream is kept whole', () async {
      final client = clientFor(ScriptedAdapter((o, i) => chunked(
            ['{"message":"a', 'b", oops', ' "end"}'],
            400,
          )));

      await expectLater(
        client.get<dynamic>('/items'),
        throwsA(isA<ClientException>().having((e) => e.responseBody,
            'responseBody', '{"message":"ab", oops "end"}')),
      );
    });
  });

  group('a success response becomes a ParsingException with its status', () {
    test('through a typed shape', () async {
      final client =
          clientFor(ScriptedAdapter((o, i) => claimingJson('{"id":', 200)));

      await expectLater(
        client.getAndDecode('/items/1', (json) => json),
        throwsA(isA<ParsingException>()
            .having((e) => e.statusCode, 'statusCode', 200)
            .having((e) => e.originalError, 'originalError',
                isA<FormatException>())),
      );
    });

    test('through a raw verb', () async {
      final client =
          clientFor(ScriptedAdapter((o, i) => claimingJson('{"id":', 200)));

      await expectLater(
        client.get<dynamic>('/items/1'),
        throwsA(isA<ParsingException>()
            .having((e) => e.statusCode, 'statusCode', 200)),
      );
    });

    test('the tracker is told the same', () async {
      final reported = <Object>[];
      final client = clientFor(
        ScriptedAdapter((o, i) => claimingJson('{"id":', 200)),
        errorTrackingConfig: ErrorTrackingConfig(
          onError: (e, {stackTrace, extra, tags}) async => reported.add(e),
        ),
      );

      await expectLater(client.get<dynamic>('/items/1'), throwsA(anything));

      expect(reported.single, isA<ParsingException>());
    });

    test('under networkFirst a stored entry answers, as for any failure',
        () async {
      final adapter = ScriptedAdapter((o, i) =>
          i == 0 ? jsonResponse({'v': 1}, 200) : claimingJson('{"v":', 200));
      final client = clientFor(
        adapter,
        cacheConfig: CacheConfig(strategy: CacheStrategy.networkFirst),
      );

      await client.get<dynamic>('/thing');
      final fallback = await client.get<dynamic>('/thing');

      expect(bodyOf(fallback)['v'], 1);
      expect(fallback.isFromCache, isTrue);
    });
  });

  group('nothing else changes', () {
    test('valid JSON decodes as before, small and past 50 KB', () async {
      final large = {'items': List.generate(4000, (i) => 'item-$i-padding')};
      expect(jsonEncode(large).length, greaterThan(50 * 1024),
          reason: 'past the size where dio 5.4.0 decodes on another isolate');
      for (final body in [
        {'id': 1},
        large,
      ]) {
        final client = clientFor(
            ScriptedAdapter((o, i) => claimingJson(jsonEncode(body), 200)));

        final response = await client.get<dynamic>('/items');

        expect(response.data, body);
      }
    });

    test('an empty JSON body is still null', () async {
      final client =
          clientFor(ScriptedAdapter((o, i) => claimingJson('', 200)));

      final response = await client.get<dynamic>('/items');

      expect(response.data, isNull);
    });

    test('a malformed Content-Type is read as text at every dio version',
        () async {
      for (final type in [ResponseType.json, ResponseType.plain]) {
        final client = clientFor(ScriptedAdapter((o, i) => claimingJson(
            'hello', 200,
            contentType: 'application/json; charset')));

        final response = await client.get<dynamic>('/items',
            options: Options(responseType: type));

        expect(response.data, 'hello', reason: type.name);
      }
    });

    test('receive progress still arrives chunk by chunk', () async {
      final events = <(int, int)>[];
      final client = clientFor(
          ScriptedAdapter((o, i) => chunked(['{"a":', '"b",', '"c":1}'], 200)));

      final response = await client.get<dynamic>(
        '/items',
        onReceiveProgress: (received, total) => events.add((received, total)),
      );

      expect(response.data, {'a': 'b', 'c': 1});
      expect(events.length, greaterThanOrEqualTo(3),
          reason: 'recorded as it streams, never gathered up front');
      expect(events.last.$1, utf8.encode('{"a":"b","c":1}').length);
    });

    test('a transport failure mid-body is not reported as a parsing failure',
        () async {
      final client = clientFor(ScriptedAdapter((o, i) {
        final controller = StreamController<Uint8List>();
        controller
          ..add(Uint8List.fromList(utf8.encode('{"a":')))
          ..addError(StateError('connection reset'))
          ..close();
        return ResponseBody(controller.stream, 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
      }));

      await expectLater(
        client.get<dynamic>('/items').timeout(const Duration(seconds: 5)),
        throwsA(isA<ApiException>()
            .having((e) => e, 'exception', isNot(isA<ParsingException>()))
            .having(
                (e) => e.originalError, 'originalError', isA<StateError>())),
      );
    });
  });
}
