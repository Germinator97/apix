import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apix/src/client/multipart_interceptor.dart';

void main() {
  group('MultipartInterceptor', () {
    late MultipartInterceptor interceptor;

    group('default JSON content type', () {
      setUp(() {
        interceptor = const MultipartInterceptor();
      });

      test('sets JSON content type for Map data without files', () async {
        final options = RequestOptions(path: '/test', data: {'key': 'value'});
        final handler = _TestHandler();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(Duration.zero);

        expect(options.contentType, equals('application/json'));
        expect(handler.nextCalled, isTrue);
      });

      test('sets JSON content type for String data', () async {
        final options = RequestOptions(path: '/test', data: 'string data');
        final handler = _TestHandler();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(Duration.zero);

        expect(options.contentType, equals('application/json'));
      });

      test('does not set content type for null data', () async {
        final options = RequestOptions(path: '/test', data: null);
        final handler = _TestHandler();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(Duration.zero);

        expect(options.contentType, isNull);
      });

      test('sets multipart content type for FormData', () async {
        final formData = FormData.fromMap({'field': 'value'});
        final options = RequestOptions(path: '/test', data: formData);
        final handler = _TestHandler();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(Duration.zero);

        expect(options.contentType, equals('multipart/form-data'));
      });

      test('respects explicitly set content type', () async {
        final options = RequestOptions(
          path: '/test',
          data: {'key': 'value'},
          contentType: 'text/plain',
        );
        final handler = _TestHandler();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(Duration.zero);

        expect(options.contentType, equals('text/plain'));
      });
    });

    group('file auto-detection', () {
      late File tempFile;
      late Directory tempDir;

      setUp(() async {
        interceptor = const MultipartInterceptor();
        tempDir = await Directory.systemTemp.createTemp('apix_test_');
        tempFile = File('${tempDir.path}/test_file.txt');
        await tempFile.writeAsString('test content');
      });

      tearDown(() async {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('detects File in map and converts to FormData', () async {
        final options = RequestOptions(
          path: '/upload',
          data: {'file': tempFile, 'name': 'test'},
        );
        final handler = _TestHandler();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(options.contentType, equals('multipart/form-data'));
        expect(options.data, isA<FormData>());
      });

      test('detects List<File> in map', () async {
        final file2 = File('${tempDir.path}/test_file2.txt');
        await file2.writeAsString('test content 2');

        final options = RequestOptions(
          path: '/upload',
          data: {
            'files': [tempFile, file2],
            'count': 2
          },
        );
        final handler = _TestHandler();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(options.contentType, equals('multipart/form-data'));
        expect(options.data, isA<FormData>());
      });

      test('does not convert map without files', () async {
        final options = RequestOptions(
          path: '/api',
          data: {'name': 'John', 'age': 30},
        );
        final handler = _TestHandler();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(Duration.zero);

        expect(options.contentType, equals('application/json'));
        expect(options.data, isA<Map<String, dynamic>>());
      });
    });

    group('custom default content type', () {
      test('uses custom default content type', () async {
        interceptor =
            const MultipartInterceptor(defaultContentType: 'text/xml');
        final options = RequestOptions(path: '/test', data: '<xml/>');
        final handler = _TestHandler();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(Duration.zero);

        expect(options.contentType, equals('text/xml'));
      });

      test('null default content type disables auto-setting', () async {
        interceptor = const MultipartInterceptor(defaultContentType: null);
        final options = RequestOptions(path: '/test', data: {'key': 'value'});
        final handler = _TestHandler();

        interceptor.onRequest(options, handler);
        await Future<void>.delayed(Duration.zero);

        expect(options.contentType, isNull);
      });
    });
  });
}

class _TestHandler extends RequestInterceptorHandler {
  bool nextCalled = false;
  bool rejectCalled = false;

  @override
  void next(RequestOptions requestOptions) {
    nextCalled = true;
  }

  @override
  void reject(DioException err, [bool callFollowingErrorInterceptor = false]) {
    rejectCalled = true;
  }
}
