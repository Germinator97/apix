import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:apix/src/http/body_preview.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../regression/audit_harness.dart';

/// A list that counts how many of its elements are read.
class _CountingList extends ListBase<int> {
  _CountingList(this.length);

  @override
  int length;

  int reads = 0;

  @override
  int operator [](int index) {
    reads++;
    return index & 0xff;
  }

  @override
  void operator []=(int index, int value) {}
}

/// A body is rendered only as far as its preview keeps.
///
/// `truncateBody` used to call `toString()` on the whole body and cut
/// afterwards. For a 5 MB PDF received as a `Uint8List` that was a
/// 24-million-character string built on the calling isolate — about 170 ms
/// per log line on a desktop — to print `[37, 80, 68, 70, …`. Measured:
/// 5 242 880 element reads to produce 1 024 characters.
void main() {
  const fiveMegabytes = 5 * 1024 * 1024;

  group('a binary body is never read', () {
    test('a 5 MB Uint8List renders as its size, in both configs', () {
      final pdf = Uint8List(fiveMegabytes);

      expect(const LoggerConfig().truncateBody(pdf), '<binary: 5242880 bytes>');
      expect(const ErrorTrackingConfig().truncateBody(pdf),
          '<binary: 5242880 bytes>');
    });

    test('at any depth', () {
      expect(
        previewBody({'file': Uint8List(3), 'name': 'report'}, 1024),
        '{file: <binary: 3 bytes>, name: report}',
      );
    });

    test('a List<int> that is not a Uint8List is a list — dio sends it as JSON',
        () {
      expect(previewBody(<int>[1, 2, 3], 1024), '[1, 2, 3]');
    });
  });

  group('a map, a list or a set renders exactly as its toString() would', () {
    final cycle = <Object>[1];
    cycle.add(cycle);
    final selfMap = <String, Object>{'id': 1};
    selfMap['self'] = selfMap;

    final samples = <Object>[
      {
        'a': 1,
        'b': [
          1,
          2,
          {'c': null}
        ],
        'd': 'text',
      },
      [1, 'two', 3.5, true, null],
      {1, 2, 3},
      <String, Object>{},
      <Object>[],
      {
        'nested': {
          'deep': {
            'deeper': [1]
          }
        }
      },
      cycle,
      selfMap,
    ];

    for (final sample in samples) {
      test('in full: ${sample.runtimeType}', () {
        expect(previewBody(sample, 1 << 20), sample.toString());
      });

      test('cut: ${sample.runtimeType}', () {
        final full = sample.toString();
        for (final limit in [0, 1, 5, full.length - 1]) {
          if (limit < 0 || limit >= full.length) continue;
          expect(previewBody(sample, limit),
              '${full.substring(0, limit)}... [truncated]',
              reason: 'limit $limit');
        }
      });
    }

    test('a large decoded response is cut like its toString()', () {
      final response = {
        'items': List.generate(10000, (i) => {'id': i, 'name': 'item $i'}),
      };

      expect(previewBody(response, 100),
          '${response.toString().substring(0, 100)}... [truncated]');
    });
  });

  group('only as far as the cut keeps', () {
    test('a five-million-element list reads a thousand elements at most', () {
      final list = _CountingList(fiveMegabytes);

      previewBody(list, 1024);

      expect(list.reads, lessThanOrEqualTo(1024),
          reason: 'every element renders at least one character');
    });
  });

  group('strings and everything else', () {
    test('a string is kept whole or cut', () {
      expect(previewBody('short', 10), 'short');
      expect(previewBody('0123456789abc', 10), '0123456789... [truncated]');
    });

    test('null renders as null', () {
      expect(previewBody(null, 10), 'null');
    });

    test('a negative limit cuts everything rather than throwing', () {
      expect(previewBody('abc', -1), '... [truncated]');
      expect(const LoggerConfig(maxBodyLength: -1).truncateBody([1]),
          '... [truncated]');
    });
  });

  group('what reaches the output', () {
    test('LoggerConfig.trace() prints a download as its size', () async {
      final printed = <String>[];
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: ScriptedAdapter((o, i) => ResponseBody.fromBytes(
              Uint8List(fiveMegabytes),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/pdf'],
              },
            )),
        loggerConfig: LoggerConfig.trace(),
      );

      await runZoned(
        () => client.get<List<int>>(
          '/files/report.pdf',
          options: Options(responseType: ResponseType.bytes),
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      expect(printed, contains('  Body: <binary: 5242880 bytes>'));
    });

    test('a tracked upload breadcrumb carries its size, not its bytes',
        () async {
      final breadcrumbs = <Map<String, dynamic>>[];
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter:
            ScriptedAdapter((o, i) => jsonResponse({'ok': true}, 200)),
        errorTrackingConfig: ErrorTrackingConfig(
          captureRequestBody: true,
          onBreadcrumb: breadcrumbs.add,
        ),
      );

      await client.put<dynamic>('/files/report.pdf',
          data: Uint8List(fiveMegabytes));

      final request = breadcrumbs.first['data'] as Map<String, dynamic>;
      expect(request['request_body'], '<binary: 5242880 bytes>');
    });
  });
}
