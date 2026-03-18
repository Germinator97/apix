import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('ApiException', () {
    test('creates with required message', () {
      const exception = ApiException(message: 'Test error');

      expect(exception.message, equals('Test error'));
      expect(exception.statusCode, isNull);
      expect(exception.originalError, isNull);
      expect(exception.stackTrace, isNull);
    });

    test('creates with all properties', () {
      final originalError = Exception('Original');
      final stackTrace = StackTrace.current;

      final exception = ApiException(
        message: 'Test error',
        statusCode: 500,
        originalError: originalError,
        stackTrace: stackTrace,
      );

      expect(exception.message, equals('Test error'));
      expect(exception.statusCode, equals(500));
      expect(exception.originalError, equals(originalError));
      expect(exception.stackTrace, equals(stackTrace));
    });

    group('toString', () {
      test('returns message without status code', () {
        const exception = ApiException(message: 'Test error');

        expect(exception.toString(), equals('ApiException: Test error'));
      });

      test('returns message with status code', () {
        const exception = ApiException(
          message: 'Not found',
          statusCode: 404,
        );

        expect(
          exception.toString(),
          equals('ApiException: Not found (status: 404)'),
        );
      });
    });

    group('equality', () {
      test('equal when message and statusCode match', () {
        const exception1 = ApiException(message: 'Error', statusCode: 500);
        const exception2 = ApiException(message: 'Error', statusCode: 500);

        expect(exception1, equals(exception2));
        expect(exception1.hashCode, equals(exception2.hashCode));
      });

      test('not equal when message differs', () {
        const exception1 = ApiException(message: 'Error 1');
        const exception2 = ApiException(message: 'Error 2');

        expect(exception1, isNot(equals(exception2)));
      });

      test('not equal when statusCode differs', () {
        const exception1 = ApiException(message: 'Error', statusCode: 400);
        const exception2 = ApiException(message: 'Error', statusCode: 500);

        expect(exception1, isNot(equals(exception2)));
      });
    });

    test('implements Exception', () {
      const exception = ApiException(message: 'Test');

      expect(exception, isA<Exception>());
    });
  });
}
