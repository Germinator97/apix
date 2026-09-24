import 'dart:convert';
import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// An error body is read the same way whatever the request asked for.
///
/// dio applies `responseType` to error responses too: one JSON envelope
/// arrives as a `Map` under `json`, as a `Uint8List` under `bytes` and as a
/// `String` under `plain`. Only the first was read, so a failed download
/// reported `HTTP 400` and no code while its body carried both — measured on
/// both dio bounds, and in the tracker as well as at the call site.
///
/// Decoding is as narrow as dio's own: a `Content-Type` that is JSON by dio's
/// rule, valid UTF-8 for bytes, well-formed JSON, under 64 KB. Everything
/// else is left exactly as received — and nothing here may throw, since it
/// runs while an error is being mapped.
void main() {
  const envelope = {
    'status': 400,
    'code': 'RANGE_TOO_WIDE',
    'message': 'The requested range is too wide.',
  };
  const rateLimited = {
    'status': 429,
    'code': 'RATE_LIMIT_EXCEEDED',
    'message': 'Too many downloads.',
  };

  ResponseBody reply(
    int status,
    List<int> body, {
    String? contentType = 'application/json',
    Map<String, List<String>> headers = const {},
  }) {
    return ResponseBody.fromBytes(body, status, headers: {
      if (contentType != null) Headers.contentTypeHeader: [contentType],
      ...headers,
    });
  }

  ApiClient clientAnswering(
    ResponseBody Function() answer, {
    ErrorTrackingConfig? tracking,
  }) {
    return ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: ScriptedAdapter((options, i) => answer()),
      errorTrackingConfig: tracking,
    );
  }

  Future<HttpException> failureOf(ApiClient client, ResponseType type) async {
    try {
      await client.get<dynamic>(
        '/files/report.pdf',
        options: Options(responseType: type),
      );
    } on HttpException catch (e) {
      return e;
    }
    fail('the request was expected to fail with an HttpException');
  }

  /// A JSON object whose UTF-8 encoding is exactly [length] bytes long.
  List<int> jsonOfLength(int length) {
    const prefix = '{"code":"BIG","message":"m","pad":"';
    final pad = 'x' * (length - prefix.length - 2);
    final bytes = utf8.encode('$prefix$pad"}');
    expect(bytes.length, length);
    return bytes;
  }

  group('a JSON error body is read whatever the responseType', () {
    for (final type in [ResponseType.bytes, ResponseType.plain]) {
      test('a 400 under ${type.name} keeps its message and its code', () async {
        final client = clientAnswering(
            () => reply(400, utf8.encode(jsonEncode(envelope))));

        final e = await failureOf(client, type);

        expect(e, isA<ClientException>());
        expect(e.statusCode, 400);
        expect(e.message, 'The requested range is too wide.');
        expect(e.code, 'RANGE_TOO_WIDE');
        expect(e.responseBody, isA<Map<String, dynamic>>());
        expect((e.responseBody as Map)['code'], 'RANGE_TOO_WIDE');
      });

      test('a 429 under ${type.name} stays typed, with its Retry-After',
          () async {
        final client = clientAnswering(() => reply(
              429,
              utf8.encode(jsonEncode(rateLimited)),
              headers: {
                'retry-after': ['30'],
              },
            ));

        final e = await failureOf(client, type);

        expect(e, isA<TooManyRequestsException>());
        expect(e.message, 'Too many downloads.');
        expect(e.code, 'RATE_LIMIT_EXCEEDED');
        expect((e as TooManyRequestsException).retryAfter,
            const Duration(seconds: 30));
      });
    }

    test('ResponseType.json is unchanged', () async {
      final client =
          clientAnswering(() => reply(400, utf8.encode(jsonEncode(envelope))));

      final e = await failureOf(client, ResponseType.json);

      expect(e.message, 'The requested range is too wide.');
      expect(e.code, 'RANGE_TOO_WIDE');
      expect(e.responseBody, isA<Map<String, dynamic>>());
    });

    test('Content-Type parameters, text/json and *+json all count as JSON',
        () async {
      for (final contentType in [
        'application/json; charset=utf-8',
        'APPLICATION/JSON',
        'text/json',
        'application/problem+json',
      ]) {
        final client = clientAnswering(() => reply(
              400,
              utf8.encode(jsonEncode(envelope)),
              contentType: contentType,
            ));

        final e = await failureOf(client, ResponseType.bytes);

        expect(e.code, 'RANGE_TOO_WIDE', reason: contentType);
      }
    });

    test('a UTF-8 byte order mark does not stop the decoding', () async {
      final client = clientAnswering(() => reply(
            400,
            [0xEF, 0xBB, 0xBF, ...utf8.encode(jsonEncode(envelope))],
          ));

      final e = await failureOf(client, ResponseType.bytes);

      expect(e.code, 'RANGE_TOO_WIDE');
    });

    test('a JSON array is decoded for responseBody, with no message or code',
        () async {
      final client = clientAnswering(
          () => reply(400, utf8.encode(jsonEncode(['first', 'second']))));

      final e = await failureOf(client, ResponseType.bytes);

      expect(e.message, 'HTTP 400');
      expect(e.code, isNull);
      expect(e.responseBody, ['first', 'second']);
    });

    test('a body of exactly 64 KB is still decoded', () async {
      final client = clientAnswering(() => reply(400, jsonOfLength(64 * 1024)));

      final e = await failureOf(client, ResponseType.bytes);

      expect(e.code, 'BIG');
    });
  });

  group('everything else is left as received, and nothing throws', () {
    Future<void> expectUndecoded(
      ResponseBody Function() answer, {
      ResponseType type = ResponseType.bytes,
      int status = 400,
    }) async {
      final e = await failureOf(clientAnswering(answer), type);

      expect(e.statusCode, status);
      expect(e.message, 'HTTP $status');
      expect(e.code, isNull);
      expect(e.responseBody,
          type == ResponseType.bytes ? isA<Uint8List>() : isA<String>());
    }

    test('an HTML page from a proxy', () async {
      await expectUndecoded(
        () => reply(502, utf8.encode('<html>Bad gateway</html>'),
            contentType: 'text/html'),
        status: 502,
      );
    });

    test('a JSON-looking body under text/plain', () async {
      await expectUndecoded(() => reply(
            400,
            utf8.encode('{"message":"m","code":"C"}'),
            contentType: 'text/plain',
          ));
    });

    test('no Content-Type at all', () async {
      await expectUndecoded(() => reply(
            400,
            utf8.encode(jsonEncode(envelope)),
            contentType: null,
          ));
    });

    test('a malformed Content-Type, which dio does not read as JSON either',
        () async {
      await expectUndecoded(() => reply(
            400,
            utf8.encode(jsonEncode(envelope)),
            contentType: 'application/json; charset',
          ));
    });

    test('invalid UTF-8 received as bytes', () async {
      await expectUndecoded(() => reply(400, [
            ...utf8.encode('{"code":"X1","message":"a'),
            0xFF,
            ...utf8.encode('b"}'),
          ]));
    });

    test('malformed JSON', () async {
      await expectUndecoded(() => reply(400, utf8.encode('{"message":"x')));
    });

    test('an empty body', () async {
      await expectUndecoded(() => reply(400, const []));
    });

    test('a body over 64 KB', () async {
      await expectUndecoded(() => reply(400, jsonOfLength(64 * 1024 + 1)));
    });

    test('a stream, which a synchronous mapper cannot read', () async {
      final e = await failureOf(
        clientAnswering(() => reply(400, utf8.encode(jsonEncode(envelope)))),
        ResponseType.stream,
      );

      expect(e.message, 'HTTP 400');
      expect(e.code, isNull);
      expect(e.responseBody, isA<ResponseBody>());
    });

    test('under plain, invalid UTF-8 was already replaced by dio', () async {
      // Documented limit: dio decodes `plain` with allowMalformed, so the
      // invalid byte is U+FFFD before apix sees the text. It is read the way
      // dio's own json path reads it at the 5.4.0 floor.
      final e = await failureOf(
        clientAnswering(() => reply(400, [
              ...utf8.encode('{"code":"X1","message":"a'),
              0xFF,
              ...utf8.encode('b"}'),
            ])),
        ResponseType.plain,
      );

      expect(e.message, 'a�b');
      expect(e.code, 'X1');
    });
  });

  group('what already held still holds on a decoded body', () {
    test('a code that repeats the status is dropped', () async {
      final client = clientAnswering(() =>
          reply(400, utf8.encode(jsonEncode({'code': 400, 'message': 'm'}))));

      final e = await failureOf(client, ResponseType.bytes);

      expect(e.code, isNull);
      expect(e.message, 'm');
    });

    test('the tracker receives the message and the code the caller gets',
        () async {
      final reported = <Object>[];
      final client = clientAnswering(
        () => reply(400, utf8.encode(jsonEncode(envelope))),
        tracking: ErrorTrackingConfig(
          captureStatusCodes: const {400},
          onError: (exception, {stackTrace, extra, tags}) async =>
              reported.add(exception),
        ),
      );

      final caught = await failureOf(client, ResponseType.bytes);

      final tracked = reported.single as ApiException;
      expect(tracked.runtimeType, caught.runtimeType);
      expect(tracked.message, caught.message);
      expect(tracked.code, caught.code);
      expect(tracked.code, 'RANGE_TOO_WIDE');
    });
  });
}
