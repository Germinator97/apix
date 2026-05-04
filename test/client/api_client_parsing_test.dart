import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adapter that returns a fixed JSON body for any request.
class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.body, {this.statusCode = 200});

  final String body;
  final int statusCode;

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
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

ApiClient _clientWithBody(String body, {int statusCode = 200}) {
  return ApiClientFactory.create(
    baseUrl: 'https://api.example.com',
    httpClientAdapter: _FixedAdapter(body, statusCode: statusCode),
  );
}

class _User {
  _User(this.id, this.name);

  factory _User.fromJson(Map<String, dynamic> json) {
    return _User(json['id'] as int, json['name'] as String);
  }

  final int id;
  final String name;
}

void main() {
  group('ApiClient parsing failure handling', () {
    test('getAndDecode throws ParsingException on shape mismatch', () async {
      final client = _clientWithBody('{"id":"not-an-int","name":"x"}');

      await expectLater(
        () => client.getAndDecode('/users/1', _User.fromJson),
        throwsA(isA<ParsingException>()),
      );
    });

    test('ParsingException is also an ApiException with statusCode preserved',
        () async {
      final client = _clientWithBody('{"id":"not-an-int"}');

      try {
        await client.getAndDecode('/users/1', _User.fromJson);
        fail('expected ParsingException');
      } on ApiException catch (e) {
        expect(e, isA<ParsingException>());
        expect(e.statusCode, equals(200));
        expect(e.originalError, isNotNull);
      }
    });

    test('getAndParse wraps user-thrown errors as ParsingException', () async {
      final client = _clientWithBody('"hello"');

      await expectLater(
        () => client.getAndParse<int>(
          '/anything',
          (data) => throw const FormatException('oops'),
        ),
        throwsA(isA<ParsingException>()),
      );
    });

    test('user-thrown ApiException is NOT re-wrapped', () async {
      final client = _clientWithBody('"x"');

      await expectLater(
        () => client.getAndParse<int>(
          '/anything',
          (data) => throw const NotFoundException(message: 'not found'),
        ),
        throwsA(
          allOf(isA<NotFoundException>(), isNot(isA<ParsingException>())),
        ),
      );
    });

    test('postAndDecodeData wraps cast failure on bad envelope', () async {
      final client = _clientWithBody('{"data":"not-a-map"}');

      await expectLater(
        () => client.postAndDecodeData(
          '/users',
          {'name': 'a'},
          _User.fromJson,
        ),
        throwsA(isA<ParsingException>()),
      );
    });

    test('getListAndDecodeData wraps element parsing failure', () async {
      final client = _clientWithBody(
        '{"data":[{"id":1,"name":"ok"},{"id":"bad","name":"x"}]}',
      );

      await expectLater(
        () => client.getListAndDecodeData('/users', _User.fromJson),
        throwsA(isA<ParsingException>()),
      );
    });

    test('successful decode still works (no regression)', () async {
      final client = _clientWithBody('{"id":1,"name":"Alex"}');

      final user = await client.getAndDecode('/users/1', _User.fromJson);

      expect(user.id, equals(1));
      expect(user.name, equals('Alex'));
    });
  });
}
