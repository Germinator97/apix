import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('Result', () {
    group('Success', () {
      test('isSuccess returns true', () {
        const result = Result<int, ApiException>.success(42);

        expect(result.isSuccess, isTrue);
        expect(result.isFailure, isFalse);
      });

      test('valueOrNull returns value', () {
        const result = Result<int, ApiException>.success(42);

        expect(result.valueOrNull, equals(42));
      });

      test('errorOrNull returns null', () {
        const result = Result<int, ApiException>.success(42);

        expect(result.errorOrNull, isNull);
      });

      test('valueOrThrow returns value', () {
        const result = Result<int, ApiException>.success(42);

        expect(result.valueOrThrow, equals(42));
      });

      test('fold calls onSuccess', () {
        const result = Result<int, ApiException>.success(42);

        final message = result.fold(
          onSuccess: (value) => 'Value: $value',
          onFailure: (error) => 'Error: ${error.message}',
        );

        expect(message, equals('Value: 42'));
      });

      test('when calls success callback', () {
        const result = Result<int, ApiException>.success(42);
        int? capturedValue;

        result.when(
          success: (value) => capturedValue = value,
          failure: (error) => fail('Should not call failure'),
        );

        expect(capturedValue, equals(42));
      });

      test('map transforms value', () {
        const result = Result<int, ApiException>.success(42);

        final mapped = result.map((value) => value * 2);

        expect(mapped.isSuccess, isTrue);
        expect(mapped.valueOrNull, equals(84));
      });

      test('mapAsync transforms value', () async {
        const result = Result<int, ApiException>.success(42);

        final mapped = await result.mapAsync((value) async => value * 2);

        expect(mapped.isSuccess, isTrue);
        expect(mapped.valueOrNull, equals(84));
      });

      test('equality', () {
        const result1 = Result<int, ApiException>.success(42);
        const result2 = Result<int, ApiException>.success(42);
        const result3 = Result<int, ApiException>.success(99);

        expect(result1, equals(result2));
        expect(result1, isNot(equals(result3)));
      });

      test('toString', () {
        const result = Result<int, ApiException>.success(42);

        expect(result.toString(), equals('Success(42)'));
      });
    });

    group('Failure', () {
      test('isFailure returns true', () {
        const error = ApiException(message: 'Error');
        const result = Result<int, ApiException>.failure(error);

        expect(result.isFailure, isTrue);
        expect(result.isSuccess, isFalse);
      });

      test('valueOrNull returns null', () {
        const error = ApiException(message: 'Error');
        const result = Result<int, ApiException>.failure(error);

        expect(result.valueOrNull, isNull);
      });

      test('errorOrNull returns error', () {
        const error = ApiException(message: 'Error');
        const result = Result<int, ApiException>.failure(error);

        expect(result.errorOrNull, equals(error));
      });

      test('valueOrThrow throws error', () {
        const error = ApiException(message: 'Error');
        const result = Result<int, ApiException>.failure(error);

        expect(() => result.valueOrThrow, throwsA(isA<ApiException>()));
      });

      test('fold calls onFailure', () {
        const error = ApiException(message: 'Test error');
        const result = Result<int, ApiException>.failure(error);

        final message = result.fold(
          onSuccess: (value) => 'Value: $value',
          onFailure: (error) => 'Error: ${error.message}',
        );

        expect(message, equals('Error: Test error'));
      });

      test('when calls failure callback', () {
        const error = ApiException(message: 'Test error');
        const result = Result<int, ApiException>.failure(error);
        ApiException? capturedError;

        result.when(
          success: (value) => fail('Should not call success'),
          failure: (e) => capturedError = e,
        );

        expect(capturedError, equals(error));
      });

      test('map preserves failure', () {
        const error = ApiException(message: 'Error');
        const result = Result<int, ApiException>.failure(error);

        final mapped = result.map((value) => value * 2);

        expect(mapped.isFailure, isTrue);
        expect(mapped.errorOrNull, equals(error));
      });

      test('mapAsync preserves failure', () async {
        const error = ApiException(message: 'Error');
        const result = Result<int, ApiException>.failure(error);

        final mapped = await result.mapAsync((value) async => value * 2);

        expect(mapped.isFailure, isTrue);
        expect(mapped.errorOrNull, equals(error));
      });

      test('equality', () {
        const error1 = ApiException(message: 'Error');
        const error2 = ApiException(message: 'Error');
        const error3 = ApiException(message: 'Different');

        const result1 = Result<int, ApiException>.failure(error1);
        const result2 = Result<int, ApiException>.failure(error2);
        const result3 = Result<int, ApiException>.failure(error3);

        expect(result1, equals(result2));
        expect(result1, isNot(equals(result3)));
      });

      test('toString', () {
        const error = ApiException(message: 'Test');
        const result = Result<int, ApiException>.failure(error);

        expect(result.toString(), contains('Failure'));
      });
    });
  });

  group('ResultExtension', () {
    test('getResult returns Success on successful future', () async {
      final future = Future.value(42);

      final result = await future.getResult();

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, equals(42));
    });

    test('getResult returns Failure on ApiException', () async {
      final future = Future<int>.error(
        const ApiException(message: 'Test error'),
      );

      final result = await future.getResult();

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, equals('Test error'));
    });

    test('getResult catches subclasses of ApiException', () async {
      final future = Future<int>.error(
        const UnauthorizedException(message: 'Not authorized'),
      );

      final result = await future.getResult();

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<UnauthorizedException>());
    });

    test('getResult rethrows non-ApiException errors', () async {
      final future = Future<int>.error(Exception('Other error'));

      expect(() => future.getResult(), throwsA(isA<Exception>()));
    });
  });
}
