import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('RequestDeduplicator', () {
    late RequestDeduplicator deduplicator;

    setUp(() {
      deduplicator = RequestDeduplicator();
    });

    test('generates unique key from method and URL', () {
      final options1 = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.test.com',
      );
      final options2 = RequestOptions(
        path: '/posts',
        method: 'GET',
        baseUrl: 'https://api.test.com',
      );

      final key1 = deduplicator.generateKey(options1);
      final key2 = deduplicator.generateKey(options2);

      expect(key1, isNot(equals(key2)));
      expect(key1, contains('GET'));
      expect(key1, contains('/users'));
    });

    test('includes body hash in key for requests with body', () {
      final options1 = RequestOptions(
        path: '/users',
        method: 'POST',
        baseUrl: 'https://api.test.com',
        data: <String, dynamic>{'name': 'John'},
      );
      final options2 = RequestOptions(
        path: '/users',
        method: 'POST',
        baseUrl: 'https://api.test.com',
        data: <String, dynamic>{'name': 'Jane'},
      );

      final key1 = deduplicator.generateKey(options1);
      final key2 = deduplicator.generateKey(options2);

      expect(key1, isNot(equals(key2)));
    });

    test('identical requests generate same key', () {
      final options1 = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.test.com',
      );
      final options2 = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.test.com',
      );

      final key1 = deduplicator.generateKey(options1);
      final key2 = deduplicator.generateKey(options2);

      expect(key1, equals(key2));
    });

    test('deduplicates concurrent identical requests', () async {
      final options = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.test.com',
      );

      int executionCount = 0;
      final completer = Completer<Response<dynamic>>();

      // Start 3 concurrent requests
      final futures = <Future<Response<dynamic>>>[];
      for (int i = 0; i < 3; i++) {
        futures.add(deduplicator.deduplicate(options, () {
          executionCount++;
          return completer.future;
        }));
      }

      // Complete the request
      completer.complete(Response<dynamic>(
        requestOptions: options,
        data: <String, dynamic>{'id': 1},
        statusCode: 200,
      ));

      final responses = await Future.wait(futures);

      // Only one execution should have happened
      expect(executionCount, equals(1));
      // All responses should be identical
      expect(responses.length, equals(3));
      for (final response in responses) {
        expect(response.data, equals({'id': 1}));
      }
    });

    test('propagates error to all waiters', () async {
      final options = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.test.com',
      );

      final completer = Completer<Response<dynamic>>();

      // Start 3 concurrent requests
      final futures = <Future<Response<dynamic>>>[];
      for (int i = 0; i < 3; i++) {
        futures.add(deduplicator.deduplicate(options, () {
          return completer.future;
        }));
      }

      // Complete with error
      completer.completeError(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'Network error',
      ));

      // All requests should fail
      for (final future in futures) {
        expect(
          () async => await future,
          throwsA(isA<DioException>()),
        );
      }
    });

    test('allows new request after previous completes', () async {
      final options = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.test.com',
      );

      int executionCount = 0;

      // First request
      final response1 = await deduplicator.deduplicate(options, () async {
        executionCount++;
        return Response<dynamic>(
          requestOptions: options,
          data: <String, dynamic>{'id': 1},
          statusCode: 200,
        );
      });

      // Second request (should execute separately)
      final response2 = await deduplicator.deduplicate(options, () async {
        executionCount++;
        return Response<dynamic>(
          requestOptions: options,
          data: <String, dynamic>{'id': 2},
          statusCode: 200,
        );
      });

      expect(executionCount, equals(2));
      expect(response1.data, equals({'id': 1}));
      expect(response2.data, equals({'id': 2}));
    });

    test('tracks pending count correctly', () async {
      final options = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.test.com',
      );

      expect(deduplicator.pendingCount, equals(0));

      final completer = Completer<Response<dynamic>>();

      // Start request
      final future = deduplicator.deduplicate(options, () => completer.future);

      // Give time for async operations
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(deduplicator.pendingCount, equals(1));
      expect(deduplicator.hasPending(options), isTrue);

      // Complete request
      completer.complete(Response<dynamic>(
        requestOptions: options,
        data: <String, dynamic>{},
        statusCode: 200,
      ));

      await future;

      expect(deduplicator.pendingCount, equals(0));
      expect(deduplicator.hasPending(options), isFalse);
    });

    test('different URLs are not deduplicated', () async {
      final options1 = RequestOptions(
        path: '/users',
        method: 'GET',
        baseUrl: 'https://api.test.com',
      );
      final options2 = RequestOptions(
        path: '/posts',
        method: 'GET',
        baseUrl: 'https://api.test.com',
      );

      int executionCount = 0;
      final completer1 = Completer<Response<dynamic>>();
      final completer2 = Completer<Response<dynamic>>();

      final future1 = deduplicator.deduplicate(options1, () {
        executionCount++;
        return completer1.future;
      });
      final future2 = deduplicator.deduplicate(options2, () {
        executionCount++;
        return completer2.future;
      });

      // Both should be pending
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(deduplicator.pendingCount, equals(2));
      expect(executionCount, equals(2));

      completer1.complete(Response<dynamic>(
        requestOptions: options1,
        data: <String, dynamic>{'type': 'users'},
        statusCode: 200,
      ));
      completer2.complete(Response<dynamic>(
        requestOptions: options2,
        data: <String, dynamic>{'type': 'posts'},
        statusCode: 200,
      ));

      final responses = await Future.wait([future1, future2]);
      expect(responses[0].data, equals({'type': 'users'}));
      expect(responses[1].data, equals({'type': 'posts'}));
    });
  });

  group('CacheConfig deduplication', () {
    test('shouldDeduplicate returns true for GET by default', () {
      final config = CacheConfig();

      expect(config.shouldDeduplicate('GET'), isTrue);
      expect(config.shouldDeduplicate('get'), isTrue);
    });

    test('shouldDeduplicate returns false for POST by default', () {
      final config = CacheConfig();

      expect(config.shouldDeduplicate('POST'), isFalse);
    });

    test('deduplication can be disabled', () {
      final config = CacheConfig(enableDeduplication: false);

      expect(config.shouldDeduplicate('GET'), isFalse);
    });

    test('custom deduplicateMethods are respected', () {
      final config = CacheConfig(
        deduplicateMethods: ['GET', 'POST'],
      );

      expect(config.shouldDeduplicate('GET'), isTrue);
      expect(config.shouldDeduplicate('POST'), isTrue);
      expect(config.shouldDeduplicate('DELETE'), isFalse);
    });
  });
}
