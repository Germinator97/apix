import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Guards on the typed-method families being available for every verb.
///
/// GET and POST had twelve variants each, PUT and PATCH had two, DELETE none —
/// because filling the gaps meant copying five hundred lines of identical
/// request-then-parse plumbing, so nobody did. The README's summary table said
/// "all verbs" regardless.
///
/// These tests exist to fail if a verb ever falls behind again: each one names
/// the method it calls, so a missing family is a compile error here rather than
/// a surprise at a call site.
void main() {
  late ScriptedAdapter adapter;
  late ApiClient client;

  setUp(() {
    adapter = ScriptedAdapter(
      (options, i) => jsonResponse({
        'data': {'id': 7, 'name': 'Jane'},
      }, 200),
    );
    client = ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
    );
  });

  String nameOf(Map<String, dynamic> json) => json['name'] as String;

  group('envelope decoding is available on every verb', () {
    test('PUT', () async {
      expect(
        await client.putAndDecodeData('/users/7', {'name': 'Jane'}, nameOf),
        'Jane',
      );
      expect(adapter.seen.single.method, 'PUT');
    });

    test('PATCH', () async {
      expect(
        await client.patchAndDecodeData('/users/7', {'name': 'Jane'}, nameOf),
        'Jane',
      );
      expect(adapter.seen.single.method, 'PATCH');
    });

    test('DELETE', () async {
      expect(
        await client.deleteAndDecodeData('/users/7', null, nameOf),
        'Jane',
      );
      expect(adapter.seen.single.method, 'DELETE');
    });

    test('GET and POST are unchanged', () async {
      expect(await client.getAndDecodeData('/users/7', nameOf), 'Jane');
      expect(
        await client.postAndDecodeData('/users', {'name': 'Jane'}, nameOf),
        'Jane',
      );
    });
  });

  group('the list families are available on every verb', () {
    setUp(() {
      adapter = ScriptedAdapter(
        (options, i) => jsonResponse({
          'data': [
            {'name': 'a'},
            {'name': 'b'},
          ],
        }, 200),
      );
      client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
      );
    });

    test('PUT returns a decoded list', () async {
      expect(
        await client.putListAndDecodeData('/bulk', <String, dynamic>{}, nameOf),
        ['a', 'b'],
      );
    });

    test('PATCH returns a decoded list', () async {
      expect(
        await client.patchListAndDecodeData(
            '/bulk', <String, dynamic>{}, nameOf),
        ['a', 'b'],
      );
    });

    test('DELETE returns a decoded list', () async {
      expect(
        await client.deleteListAndDecodeData('/bulk', null, nameOf),
        ['a', 'b'],
      );
    });
  });

  group('the absent-payload variants behave per verb', () {
    setUp(() {
      adapter = ScriptedAdapter(
        (options, i) => jsonResponse({'data': null}, 200),
      );
      client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
      );
    });

    test('OrNull yields null, OrEmpty yields an empty list', () async {
      expect(
        await client.putAndDecodeDataOrNull('/x', <String, dynamic>{}, nameOf),
        isNull,
      );
      expect(
        await client.patchListAndDecodeDataOrEmpty(
            '/x', <String, dynamic>{}, nameOf),
        isEmpty,
      );
      expect(
        await client.deleteListAndParseDataOrNull('/x', null, (item) => item),
        isNull,
      );
    });
  });

  test('the verb reaches the wire, not just the typed wrapper', () async {
    // The shared core sets the method through Options.copyWith, so a mistake
    // there would silently send every typed call as the same verb — and every
    // assertion above would still pass on a server that ignores the method.
    await client.putAndParse('/x', <String, dynamic>{}, (data) => data);
    await client.patchAndParse('/x', <String, dynamic>{}, (data) => data);
    await client.deleteAndParse('/x', null, (data) => data);

    expect(adapter.seen.map((o) => o.method), ['PUT', 'PATCH', 'DELETE']);
  });

  test('options supplied by the caller survive the method override', () async {
    await client.putAndParse(
      '/x',
      <String, dynamic>{},
      (data) => data,
      options: Options(headers: {'X-Trace': 'abc'}),
    );

    expect(adapter.seen.single.method, 'PUT');
    expect(adapter.seen.single.headers['X-Trace'], 'abc',
        reason: 'copyWith(method:) must not drop what the caller passed');
  });
}
