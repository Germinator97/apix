import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('NetworkException', () {
    test('extends ApiException', () {
      const exception = NetworkException(message: 'Network error');

      expect(exception, isA<ApiException>());
    });

    test('creates with required message', () {
      const exception = NetworkException(message: 'Network error');

      expect(exception.message, equals('Network error'));
      expect(exception.statusCode, isNull);
      expect(exception.originalError, isNull);
    });

    test('toString returns formatted message', () {
      const exception = NetworkException(message: 'No internet');

      expect(exception.toString(), equals('NetworkException: No internet'));
    });
  });

  group('TimeoutException', () {
    test('extends NetworkException', () {
      const exception = TimeoutException(message: 'Timeout');

      expect(exception, isA<NetworkException>());
      expect(exception, isA<ApiException>());
    });

    test('creates with message only', () {
      const exception = TimeoutException(message: 'Request timed out');

      expect(exception.message, equals('Request timed out'));
      expect(exception.duration, isNull);
    });

    test('creates with duration', () {
      const exception = TimeoutException(
        message: 'Request timed out',
        duration: Duration(seconds: 30),
      );

      expect(exception.duration, equals(const Duration(seconds: 30)));
    });

    test('toString without duration', () {
      const exception = TimeoutException(message: 'Timeout');

      expect(exception.toString(), equals('TimeoutException: Timeout'));
    });

    test('toString with duration', () {
      const exception = TimeoutException(
        message: 'Timeout',
        duration: Duration(milliseconds: 5000),
      );

      expect(
        exception.toString(),
        equals('TimeoutException: Timeout (after 5000ms)'),
      );
    });
  });

  group('ConnectionException', () {
    test('extends NetworkException', () {
      const exception = ConnectionException(message: 'Connection failed');

      expect(exception, isA<NetworkException>());
      expect(exception, isA<ApiException>());
    });

    test('creates with required message', () {
      const exception = ConnectionException(message: 'No connection');

      expect(exception.message, equals('No connection'));
    });

    test('toString returns formatted message', () {
      const exception = ConnectionException(message: 'Cannot reach server');

      expect(
        exception.toString(),
        equals('ConnectionException: Cannot reach server'),
      );
    });

    test('can be caught as NetworkException', () {
      Exception? caught;

      try {
        throw const ConnectionException(message: 'Test');
      } on NetworkException catch (e) {
        caught = e;
      }

      expect(caught, isA<ConnectionException>());
    });

    test('can be caught as ApiException', () {
      Exception? caught;

      try {
        throw const TimeoutException(message: 'Test');
      } on ApiException catch (e) {
        caught = e;
      }

      expect(caught, isA<TimeoutException>());
    });
  });
}
