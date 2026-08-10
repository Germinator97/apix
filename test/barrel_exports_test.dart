// Deliberately NOT importing package:dio here. That absence is the whole
// assertion: every symbol below has to resolve through apix's own entry points,
// which is exactly what a consumer gets. Add a dio import and this file stops
// testing anything.
import 'dart:convert';

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uses only types re-exported by apix — no dio import in sight.
class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'data': 'ok'})),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A custom interceptor, the case `ApiClientFactory.create(interceptors:)`
/// invites and that was impossible to write without importing dio.
class _StampingInterceptor extends Interceptor {
  var stamped = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    stamped = true;
    handler.next(options);
  }
}

void main() {
  group('apix barrel', () {
    test('a binary download can be requested without importing dio', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: _StubAdapter(),
      );

      // ResponseType is the symbol that was missing: without it, every binary
      // download kept a direct dio import.
      final response = await client.get<dynamic>(
        '/statement.pdf',
        options: Options(responseType: ResponseType.bytes),
      );

      expect(response.statusCode, equals(200));
    });

    test('a custom interceptor can be written without importing dio', () async {
      final interceptor = _StampingInterceptor();
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        interceptors: [interceptor],
        httpClientAdapter: _StubAdapter(),
      );

      await client.get<dynamic>('/ping');

      expect(interceptor.stamped, isTrue);
    });

    test('per-request extensions reach RequestOptions', () {
      final options = RequestOptions(path: '/x')
        ..disableRetry()
        ..noCache();

      expect(options.isNoRetry, isTrue);
    });

    test('uploads can be built without importing dio', () {
      final form = FormData.fromMap({'field': 'value'});

      expect(form.fields, isNotEmpty);
      expect(MultipartFile.fromString('body'), isNotNull);
    });

    test('response headers are readable without importing dio', () {
      final headers = Headers.fromMap({
        'retry-after': ['30'],
      });

      expect(headers.value('retry-after'), equals('30'));
    });

    test('error types from a custom interceptor resolve', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.cancel,
      );

      expect(err.type, equals(DioExceptionType.cancel));
    });
  });
}
