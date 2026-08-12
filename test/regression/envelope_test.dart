import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on envelope unwrapping.
///
/// The defect here fires under HTTP 200, on the user who simply has no data
/// yet — the one case nobody exercises while building a feature.
void main() {
  ApiClient clientFor(ScriptedAdapter adapter) => ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
      );

  Map<String, dynamic> asIs(Map<String, dynamic> json) => json;

  group('M9 — an empty collection spelled as a bare array', () {
    test('…OrEmpty returns an empty list', () async {
      final client = clientFor(
        ScriptedAdapter((options, i) => jsonResponse(<dynamic>[], 200)),
      );

      final users =
          await client.getListAndDecodeDataOrEmpty<Map<String, dynamic>>(
        '/users',
        asIs,
      );

      expect(users, isEmpty);
    });

    test('…OrNull returns an empty list rather than throwing', () async {
      final client = clientFor(
        ScriptedAdapter((options, i) => jsonResponse(<dynamic>[], 200)),
      );

      final users =
          await client.getListAndDecodeDataOrNull<Map<String, dynamic>>(
        '/users',
        asIs,
      );

      expect(users, isEmpty);
    });

    test('a populated bare array is read as the payload', () async {
      final client = clientFor(
        ScriptedAdapter(
          (options, i) => jsonResponse([
            {'id': 1},
            {'id': 2},
          ], 200),
        ),
      );

      final users = await client.getListAndDecodeData<Map<String, dynamic>>(
        '/users',
        asIs,
      );

      expect(users, hasLength(2));
      expect(users.first['id'], 1);
    });

    test('a bare null body is treated as no data', () async {
      final client = clientFor(
        ScriptedAdapter((options, i) => jsonResponse(null, 200)),
      );

      final users =
          await client.getListAndDecodeDataOrEmpty<Map<String, dynamic>>(
        '/users',
        asIs,
      );

      expect(users, isEmpty);
    });

    test('the proper envelope still wins over the root', () async {
      final client = clientFor(
        ScriptedAdapter(
          (options, i) => jsonResponse({
            'data': [
              {'id': 7},
            ],
            'total': 1,
          }, 200),
        ),
      );

      // The direction that must not move: tolerating a bare array must not
      // start ignoring the envelope when there is one.
      final users = await client.getListAndDecodeData<Map<String, dynamic>>(
        '/users',
        asIs,
      );

      expect(users.single['id'], 7);
    });

    test('an envelope holding an empty list still works', () async {
      final client = clientFor(
        ScriptedAdapter(
          (options, i) => jsonResponse({'data': <dynamic>[]}, 200),
        ),
      );

      final users =
          await client.getListAndDecodeDataOrEmpty<Map<String, dynamic>>(
        '/users',
        asIs,
      );

      expect(users, isEmpty);
    });

    test('a shape nobody can guess at still fails clearly', () async {
      final client = clientFor(
        ScriptedAdapter((options, i) => jsonResponse('surprise', 200)),
      );

      // Tolerance has a limit: a bare string is not an envelope and not a
      // collection, and silently inventing a payload would be worse.
      await expectLater(
        client.getListAndDecodeDataOrEmpty<Map<String, dynamic>>(
            '/users', asIs),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
