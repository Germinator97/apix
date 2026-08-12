@TestOn('vm')
library;

import 'dart:io';

import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import '../regression/audit_harness.dart';

/// Guards that the typed methods can report progress.
///
/// The raw verbs took `onSendProgress` / `onReceiveProgress`; the sixty typed
/// ones did not, so a typed upload with a progress bar was not expressible and
/// the only way to get one was to drop back to `client.post` and parse by hand
/// — losing the typing that is the whole point of those methods.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/src/client/api_client.dart').readAsStringSync();
  });

  ApiClient clientWith(ScriptedAdapter adapter) => ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
      );

  group('the callbacks reach dio', () {
    test('a typed POST forwards onSendProgress', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({
          'data': {'id': 1},
        }, 200),
      );
      RequestOptions? seen;
      final client = clientWith(adapter);

      await client.postAndDecodeData<int>(
        '/upload',
        {'name': 'x'},
        (json) => json['id'] as int,
        onSendProgress: (sent, total) {},
        onReceiveProgress: (received, total) {},
      );

      seen = adapter.seen.single;
      expect(seen.onSendProgress, isNotNull,
          reason: 'the parameter has to arrive at dio, not merely compile');
      expect(seen.onReceiveProgress, isNotNull);
    });

    test('a typed GET forwards onReceiveProgress', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({
          'data': {'id': 1},
        }, 200),
      );
      final client = clientWith(adapter);

      await client.getAndDecodeData<int>(
        '/thing',
        (json) => json['id'] as int,
        onReceiveProgress: (received, total) {},
      );

      expect(adapter.seen.single.onReceiveProgress, isNotNull);
    });

    test('omitting them changes nothing', () async {
      final adapter = ScriptedAdapter(
        (options, i) => jsonResponse({
          'data': {'id': 7},
        }, 200),
      );
      final client = clientWith(adapter);

      expect(
        await client.getAndDecodeData<int>('/thing', (j) => j['id'] as int),
        7,
      );
      expect(adapter.seen.single.onReceiveProgress, isNull);
    });
  });

  group('every typed family got them, not the ones easy to remember', () {
    /// Counts the public typed methods and how many carry each callback.
    ///
    /// Reading the source rather than calling all sixty: the risk here is not
    /// that one method misbehaves, it is that a family was **skipped** — which
    /// is exactly how GET and POST ended up with twelve variants each while
    /// PUT had two and DELETE none.
    ({int total, int withReceive, int withSend, int withBody}) survey() {
      // Scoped to the typed section: the five raw verbs above it share the
      // same declaration shape, and counting them made every number here five
      // too high while the test still read as if it were measuring something.
      final marker = source.indexOf('  // ---------- GET ----------');
      expect(marker, isNot(-1),
          reason: 'the section marker moved — fix this parsing, do not delete '
              'the test');

      final declarations = RegExp(
        r'  Future<[^\n]*> \w+<T>\(\n(.*?)\n  \}\n',
        dotAll: true,
      ).allMatches(source.substring(marker)).map((m) => m.group(1)!).toList();

      return (
        total: declarations.length,
        withReceive: declarations
            .where((d) => d.contains('onReceiveProgress: onReceiveProgress,'))
            .length,
        withSend: declarations
            .where((d) => d.contains('onSendProgress: onSendProgress,'))
            .length,
        withBody: declarations
            .where((d) =>
                RegExp(r'^\s*Object\? data,$', multiLine: true).hasMatch(d))
            .length,
      );
    }

    test('the survey found the methods at all', () {
      expect(survey().total, 60,
          reason: 'twelve shapes across five verbs — if this number moved, '
              'the parsing here is stale and every assertion below is vacant');
    });

    test('all sixty can report receive progress', () {
      final counts = survey();
      expect(counts.withReceive, counts.total);
    });

    test('every body-bearing one can report send progress', () {
      final counts = survey();
      expect(counts.withBody, 48,
          reason: 'POST, PUT, PATCH and DELETE take a body; GET does not');
      expect(counts.withSend, counts.withBody);
    });

    test('the body-less ones do not pretend to', () {
      final counts = survey();
      expect(counts.total - counts.withSend, 12,
          reason: 'a GET has nothing to send, and an option that can never '
              'fire is an option that looks set');
    });
  });
}
