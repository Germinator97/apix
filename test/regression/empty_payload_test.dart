import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on **every shape a backend uses to say "nothing"**.
///
/// M9 closed one of them — a bare `[]` where an envelope was expected. Ma
/// Pension's a review point pointed out that there are three, and that which one you get is
/// not a property of your API but of a serialiser flag: Jackson's
/// `default-property-inclusion: non_empty` removes the `data` key entirely from
/// every empty collection, where `non_null` keeps `"data":[]`.
///
/// So a consumer's immunity here does not come from the shape of their
/// responses. It comes from one line of server configuration that no test on
/// either side watches — which is exactly why the tolerant variants have to
/// accept all three, and why that has to be pinned rather than left to the
/// accident of a Map lookup returning null.
void main() {
  ApiClient clientReturning(Object? body) => ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter:
            ScriptedAdapter((options, i) => jsonResponse(body, 200)),
      );

  /// The four ways the wire says "no data", named as a consumer would meet them.
  const shapes = <String, Object?>{
    'a bare [] at the root': <dynamic>[],
    'data explicitly null': {'code': 200, 'data': null},
    'the data key absent (Jackson non_empty)': {'code': 200, 'message': 'ok'},
    'no body at all': null,
  };

  group('OrEmpty tolerates every shape of empty', () {
    shapes.forEach((name, body) {
      test(name, () async {
        expect(
          await clientReturning(body)
              .getListAndDecodeDataOrEmpty<int>('/x', (j) => j['id'] as int),
          isEmpty,
        );
      });
    });

    test('and the parse family too', () async {
      for (final body in shapes.values) {
        expect(
          await clientReturning(body)
              .getListAndParseDataOrEmpty<int>('/x', (i) => i as int),
          isEmpty,
        );
      }
    });
  });

  group('OrNull tolerates every shape of empty', () {
    shapes.forEach((name, body) {
      test(name, () async {
        final decoded = await clientReturning(body)
            .getListAndDecodeDataOrNull<int>('/x', (j) => j['id'] as int);
        // A bare `[]` is an empty list, not an absence: the server said "none",
        // which is an answer. The other three are absences.
        expect(decoded, body is List ? isEmpty : isNull);
      });
    });

    test('the single-object variant too', () async {
      for (final body in shapes.values.where((b) => b is! List)) {
        expect(
          await clientReturning(body)
              .getAndDecodeDataOrNull<int>('/x', (j) => j['id'] as int),
          isNull,
        );
      }
    });
  });

  group('the strict variants refuse, and say why', () {
    test('a missing payload names the key and the way out', () async {
      await expectLater(
        clientReturning({'code': 200, 'message': 'ok'})
            .getListAndDecodeData<int>('/x', (j) => j['id'] as int),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('"data"'),
              contains('OrEmpty'),
              isNot(contains('is not a subtype')),
            ),
          ),
        ),
      );
    });

    test('the single-object variant says the same', () async {
      await expectLater(
        clientReturning({'code': 200}).getAndDecodeData<int>(
          '/x',
          (j) => j['id'] as int,
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('"data"'))),
      );
    });

    test('the key that is named is the configured one', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        dataKey: 'payload',
        httpClientAdapter:
            ScriptedAdapter((options, i) => jsonResponse({'code': 200}, 200)),
      );

      await expectLater(
        client.getListAndDecodeData<int>('/x', (j) => j['id'] as int),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('"payload"'))),
      );
    });
  });

  group('a present payload is still decoded', () {
    // The half a tolerance fix cuts too far: accepting every absence must not
    // start accepting a body that is there.
    test('a populated list decodes normally', () async {
      final client = clientReturning({
        'data': [
          {'id': 1},
          {'id': 2},
        ],
      });

      expect(
        await client.getListAndDecodeDataOrEmpty<int>(
            '/x', (j) => j['id'] as int),
        [1, 2],
      );
    });

    test('a payload of the wrong shape still fails', () async {
      await expectLater(
        clientReturning({'data': 'not a list'})
            .getListAndDecodeDataOrEmpty<int>('/x', (j) => j['id'] as int),
        throwsA(isA<ParsingException>()),
      );
    });
  });
}
