import 'dart:convert';
import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// The binary shape: a body read as bytes and handed back with its status
/// and headers, on every verb, typed like every other shape.
///
/// The raw verbs could already download a file, and left each caller to
/// force `ResponseType.bytes` (forgetting it corrupts the file silently),
/// to check the body is the expected type (a captive portal's page served as
/// `200` would be saved as a PDF), to parse the file name, and to carry a dio
/// `Response` into its data layer to do it.
void main() {
  /// Starts like a PDF and is neither valid UTF-8 nor JSON: a body that any
  /// decoding would damage.
  final pdf = Uint8List.fromList([
    ...ascii.encode('%PDF-1.7\n'),
    0xFF,
    0x00,
    0xC3,
    0x28,
    0x80,
    ...ascii.encode('\n%%EOF'),
  ]);

  ResponseBody pdfResponse({
    int status = 200,
    List<int>? body,
    String? contentType = 'application/pdf',
    Map<String, List<String>> headers = const {},
  }) {
    return ResponseBody.fromBytes(body ?? pdf, status, headers: {
      if (contentType != null) Headers.contentTypeHeader: [contentType],
      ...headers,
    });
  }

  ApiClient clientFor(
    ScriptedAdapter adapter, {
    CacheConfig? cacheConfig,
    ResponseValidator? responseValidator,
  }) {
    return ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
      cacheConfig: cacheConfig,
      responseValidator: responseValidator,
    );
  }

  group('a file comes back whole, with what describes it', () {
    test('bytes, status, type, file name and a business header', () async {
      final client = clientFor(ScriptedAdapter((o, i) => pdfResponse(
            headers: {
              'content-disposition': [
                'attachment; filename="report-2026-06.pdf"'
              ],
              'x-missing-items': ['2026-07'],
            },
          )));

      final file = await client.getAndReadBytes(
        '/reports',
        queryParameters: {'from': '2026-06', 'to': '2026-08'},
        expectedContentTypes: ['application/pdf'],
      );

      expect(file.bytes, pdf);
      expect(file.statusCode, 200);
      expect(file.contentType, 'application/pdf');
      expect(file.fileName, 'report-2026-06.pdf');
      expect(file.header('X-Missing-Items'), '2026-07');
      expect(file.isEmpty, isFalse);
    });

    test('filename* wins over filename', () async {
      final client = clientFor(ScriptedAdapter((o, i) => pdfResponse(
            headers: {
              'content-disposition': [
                "attachment; filename=\"plain.pdf\"; filename*=UTF-8''r%C3%A9sum%C3%A9.pdf"
              ],
            },
          )));

      final file = await client.getAndReadBytes('/reports');

      expect(file.fileName, 'résumé.pdf');
    });

    test('a 204 is empty, and raises nothing — expected type or not', () async {
      final client = clientFor(
          ScriptedAdapter((o, i) => ResponseBody.fromBytes(const [], 204)));

      final file = await client.getAndReadBytes('/reports',
          expectedContentTypes: ['application/pdf']);

      expect(file.isEmpty, isTrue);
      expect(file.statusCode, 204);
    });
  });

  group('the expected type is checked', () {
    test('an HTML page served as 200 is refused', () async {
      final client = clientFor(ScriptedAdapter((o, i) => pdfResponse(
            body: utf8.encode('<html>Sign in to the Wi-Fi</html>'),
            contentType: 'text/html',
          )));

      await expectLater(
        client.getAndReadBytes('/reports',
            expectedContentTypes: ['application/pdf']),
        throwsA(isA<UnexpectedContentTypeException>()
            .having((e) => e.expectedContentType, 'expected', 'application/pdf')
            .having((e) => e.actualContentType, 'actual', 'text/html')
            .having((e) => e.statusCode, 'statusCode', 200)),
      );
    });

    test('type parameters are tolerated, and the case ignored', () async {
      final client = clientFor(ScriptedAdapter((o, i) =>
          pdfResponse(contentType: 'Application/PDF; charset=binary')));

      final file = await client.getAndReadBytes('/reports',
          expectedContentTypes: ['application/pdf']);

      expect(file.bytes, pdf);
    });

    test('type/* accepts its whole family, and the list is named when refused',
        () async {
      final png = clientFor(
          ScriptedAdapter((o, i) => pdfResponse(contentType: 'image/png')));
      expect(
        (await png.getAndReadBytes('/logo',
                expectedContentTypes: ['application/pdf', 'image/*']))
            .contentType,
        'image/png',
      );

      final zip = clientFor(ScriptedAdapter(
          (o, i) => pdfResponse(contentType: 'application/zip')));
      await expectLater(
        zip.getAndReadBytes('/logo',
            expectedContentTypes: ['application/pdf', 'image/*']),
        throwsA(isA<UnexpectedContentTypeException>().having(
            (e) => e.expectedContentType,
            'expected',
            'application/pdf, image/*')),
      );
    });

    test('a missing Content-Type is refused when a type is expected', () async {
      final client =
          clientFor(ScriptedAdapter((o, i) => pdfResponse(contentType: null)));

      await expectLater(
        client.getAndReadBytes('/reports',
            expectedContentTypes: ['application/pdf']),
        throwsA(isA<UnexpectedContentTypeException>()
            .having((e) => e.actualContentType, 'actual', isNull)),
      );
    });

    test('without an expected type, any body is returned', () async {
      final client = clientFor(ScriptedAdapter((o, i) => pdfResponse(
          body: utf8.encode('<html></html>'), contentType: 'text/html')));

      final file = await client.getAndReadBytes('/reports');

      expect(file.contentType, 'text/html');
    });
  });

  group('the request is the one the caller asked for', () {
    test('bytes are forced, even over an explicit ResponseType.json', () async {
      final adapter = ScriptedAdapter((o, i) => pdfResponse(
          contentType: 'application/json')); // a lying header, a real PDF
      final client = clientFor(adapter);

      final file = await client.getAndReadBytes('/reports',
          options: Options(responseType: ResponseType.json));

      expect(file.bytes, pdf,
          reason: 'decoded as JSON or text, it would be '
              'corrupted or refused');
      expect(adapter.seen.single.responseType, ResponseType.bytes);
    });

    test('the rest of the options is kept — a longer receiveTimeout', () async {
      final adapter = ScriptedAdapter((o, i) => pdfResponse());
      final client = clientFor(adapter);

      await client.getAndReadBytes('/reports',
          options: Options(receiveTimeout: const Duration(minutes: 2)));

      expect(adapter.seen.single.receiveTimeout, const Duration(minutes: 2));
    });

    test('Accept is not narrowed, and the caller\'s own is kept', () async {
      final adapter = ScriptedAdapter((o, i) => pdfResponse());
      final client = clientFor(adapter);

      await client.getAndReadBytes('/reports',
          expectedContentTypes: ['application/pdf']);
      await client.getAndReadBytes('/reports',
          options: Options(
              headers: {'Accept': 'application/pdf, application/json'}));

      expect(adapter.seen[0].headers['accept'], isNull);
      expect(adapter.seen[1].headers['accept'],
          'application/pdf, application/json');
    });
  });

  group('failures are typed like everywhere else', () {
    test('a JSON error gives its message and code, although bytes were asked',
        () async {
      final client = clientFor(ScriptedAdapter((o, i) => jsonResponse(
            {'code': 'RANGE_TOO_WIDE', 'message': 'The range is too wide.'},
            400,
          )));

      await expectLater(
        client.getAndReadBytes('/reports'),
        throwsA(isA<ClientException>()
            .having((e) => e.message, 'message', 'The range is too wide.')
            .having((e) => e.code, 'code', 'RANGE_TOO_WIDE')),
      );
    });

    test('a 429 keeps its code and its Retry-After', () async {
      final client = clientFor(ScriptedAdapter((o, i) => jsonResponse(
            {'code': 'RATE_LIMIT_EXCEEDED', 'message': 'Slow down.'},
            429,
            headers: {
              'retry-after': ['120'],
            },
          )));

      await expectLater(
        client.getAndReadBytes('/reports'),
        throwsA(isA<TooManyRequestsException>()
            .having((e) => e.code, 'code', 'RATE_LIMIT_EXCEEDED')
            .having(
                (e) => e.retryAfter, 'retryAfter', const Duration(minutes: 2))),
      );
    });
  });

  group('every verb reads bytes', () {
    final verbs = <String,
        Future<BinaryResponse> Function(ApiClient client, Object? data)>{
      'POST': (c, d) => c.postAndReadBytes('/render', d),
      'PUT': (c, d) => c.putAndReadBytes('/render', d),
      'PATCH': (c, d) => c.patchAndReadBytes('/render', d),
      'DELETE': (c, d) => c.deleteAndReadBytes('/render', d),
    };

    verbs.forEach((method, call) {
      test(method, () async {
        final adapter = ScriptedAdapter((o, i) => pdfResponse());
        final client = clientFor(adapter);

        final file = await call(client, {'template': 'monthly'});

        expect(file.bytes, pdf);
        expect(adapter.seen.single.method, method);
        expect(adapter.seen.single.data, {'template': 'monthly'});
      });
    });
  });

  group('around the shape', () {
    test('a cache hit returns the same bytes, headers and file name', () async {
      final adapter = ScriptedAdapter((o, i) => pdfResponse(headers: {
            'content-disposition': ['attachment; filename="report.pdf"'],
            'x-tag': ['a', 'b'],
          }));
      final client = clientFor(adapter,
          cacheConfig: CacheConfig(strategy: CacheStrategy.cacheFirst));

      final live = await client.getAndReadBytes('/reports');
      final cached = await client.getAndReadBytes('/reports');

      expect(adapter.callCount, 1);
      expect(cached.bytes, live.bytes);
      expect(cached.fileName, live.fileName);
      expect(cached.header('x-tag'), live.header('x-tag'));
    });

    test('a responseValidator sees the bytes — one that ignores them passes',
        () async {
      Object? seen;
      final client = clientFor(
        ScriptedAdapter((o, i) => pdfResponse()),
        responseValidator: (response) {
          seen = response.data;
          final data = response.data;
          if (data is! Map) return null; // the idiom the docs show
          return null;
        },
      );

      await client.getAndReadBytes('/reports');

      expect(seen, isA<Uint8List>());
    });
  });
}
