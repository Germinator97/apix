import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ContentTypeAdapter implements HttpClientAdapter {
  _ContentTypeAdapter(this.body, {this.contentType = 'application/json'});

  final String body;
  final String? contentType;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        if (contentType != null) Headers.contentTypeHeader: [contentType!],
      },
    );
  }
}

class _User {
  _User(this.id);

  factory _User.fromJson(Map<String, dynamic> json) => _User(json['id'] as int);

  final int id;
}

void main() {
  group('ApiClient strictContentType', () {
    test('default (off) does not raise UnexpectedContentTypeException',
        () async {
      // Strict mode is OFF: even with a "wrong" content-type the new
      // exception type is never thrown. (The body still has to be a JSON
      // object for `*AndDecode` — that constraint predates 11.5.)
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        httpClientAdapter: _ContentTypeAdapter(
          '{"id":1}',
          contentType: 'application/json',
        ),
      );

      final user = await client.getAndDecode('/x', _User.fromJson);
      expect(user.id, equals(1));
    });

    test(
      'strict mode throws UnexpectedContentTypeException for non-JSON',
      () async {
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          strictContentType: true,
          httpClientAdapter: _ContentTypeAdapter(
            '<html>captive portal</html>',
            contentType: 'text/html',
          ),
        );

        try {
          await client.getAndDecode('/x', _User.fromJson);
          fail('expected UnexpectedContentTypeException');
        } on UnexpectedContentTypeException catch (e) {
          expect(e.expectedContentType, equals('application/json'));
          expect(e.actualContentType, equals('text/html'));
          expect(e.statusCode, equals(200));
        }
      },
    );

    test('strict mode passes for application/json with charset', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        strictContentType: true,
        httpClientAdapter: _ContentTypeAdapter(
          '{"id":7}',
          contentType: 'application/json; charset=utf-8',
        ),
      );

      final user = await client.getAndDecode('/x', _User.fromJson);
      expect(user.id, equals(7));
    });

    test('strict mode is case-insensitive', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        strictContentType: true,
        httpClientAdapter: _ContentTypeAdapter(
          '{"id":3}',
          contentType: 'Application/JSON',
        ),
      );

      final user = await client.getAndDecode('/x', _User.fromJson);
      expect(user.id, equals(3));
    });

    test('strict mode throws when Content-Type header is missing', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        strictContentType: true,
        httpClientAdapter: _ContentTypeAdapter(
          '{"id":3}',
          contentType: null,
        ),
      );

      try {
        await client.getAndDecode('/x', _User.fromJson);
        fail('expected UnexpectedContentTypeException');
      } on UnexpectedContentTypeException catch (e) {
        expect(e.actualContentType, isNull);
      }
    });

    test('*AndParse is unaffected by strict mode', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        strictContentType: true,
        httpClientAdapter: _ContentTypeAdapter(
          'plain text',
          contentType: 'text/plain',
        ),
      );

      // *AndParse doesn't enforce JSON content-type even in strict mode.
      final value = await client.getAndParse(
        '/x',
        (data) => data as String,
      );
      expect(value, equals('plain text'));
    });

    test(
      'UnexpectedContentTypeException is catchable as ApiException',
      () async {
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          strictContentType: true,
          httpClientAdapter: _ContentTypeAdapter(
            '<html/>',
            contentType: 'text/html',
          ),
        );

        try {
          await client.getAndDecode('/x', _User.fromJson);
          fail('expected exception');
        } on ApiException catch (e) {
          expect(e, isA<UnexpectedContentTypeException>());
        }
      },
    );
  });
}
