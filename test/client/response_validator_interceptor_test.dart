import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _BusinessException extends ApiException {
  const _BusinessException(String code, String message)
      : businessCode = code,
        super(message: message, statusCode: 200);

  final String businessCode;
}

void main() {
  group('responseValidator', () {
    test('null validator → response passes through (default behavior)',
        () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        httpClientAdapter: _FixedAdapter('{"success":true}'),
      );

      final response = await client.get<dynamic>('/x');
      expect(response.statusCode, equals(200));
    });

    test(
      'validator returning ApiException → request fails with that exception',
      () async {
        var validatorCalls = 0;
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          httpClientAdapter: _FixedAdapter(
            '{"success":false,"error":"INSUFFICIENT_FUNDS"}',
          ),
          responseValidator: (response) {
            validatorCalls++;
            final body = response.data;
            if (body is Map && body['success'] == false) {
              return _BusinessException(
                body['error'] as String,
                'Business error',
              );
            }
            return null;
          },
        );

        try {
          await client.get<dynamic>('/x');
          fail('expected _BusinessException');
        } on ApiException catch (e) {
          expect(e, isA<_BusinessException>());
          expect((e as _BusinessException).businessCode,
              equals('INSUFFICIENT_FUNDS'));
        }
        expect(validatorCalls, equals(1));
      },
    );

    test('validator returning null → response passes through', () async {
      var validatorCalls = 0;
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        httpClientAdapter: _FixedAdapter('{"success":true,"data":{"id":1}}'),
        responseValidator: (response) {
          validatorCalls++;
          return null;
        },
      );

      final response = await client.get<dynamic>('/x');
      expect(response.statusCode, equals(200));
      expect(validatorCalls, equals(1));
    });

    test('validator NOT called on 4xx response', () async {
      var validatorCalls = 0;
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        httpClientAdapter: _FixedAdapter(
          '{"error":"not found"}',
          statusCode: 404,
        ),
        responseValidator: (response) {
          validatorCalls++;
          return null;
        },
      );

      await expectLater(
        () => client.get<dynamic>('/x'),
        throwsA(isA<NotFoundException>()),
      );
      expect(validatorCalls, equals(0));
    });

    test('validator that throws → wrapped in ApiException with originalError',
        () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        httpClientAdapter: _FixedAdapter('{"x":1}'),
        responseValidator: (response) {
          throw const FormatException('validator boom');
        },
      );

      try {
        await client.get<dynamic>('/x');
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.message, contains('responseValidator threw'));
        expect(e.originalError, isA<FormatException>());
      }
    });

    test('preserves the exact subclass returned by the validator', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        httpClientAdapter: _FixedAdapter('{}'),
        responseValidator: (response) =>
            const ForbiddenException(message: 'no'),
      );

      await expectLater(
        () => client.get<dynamic>('/x'),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });
}
