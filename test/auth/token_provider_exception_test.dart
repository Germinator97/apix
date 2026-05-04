import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TokenProviderException', () {
    test('extends ApiException and Exception', () {
      const e = TokenProviderException(
        operation: TokenProviderOperation.read,
        message: 'fail',
      );

      expect(e, isA<ApiException>());
      expect(e, isA<Exception>());
    });

    test('exposes operation', () {
      const e = TokenProviderException(
        operation: TokenProviderOperation.write,
        message: 'fail',
      );

      expect(e.operation, equals(TokenProviderOperation.write));
    });

    test('toString includes operation name', () {
      const e = TokenProviderException(
        operation: TokenProviderOperation.read,
        message: 'keychain corrupted',
      );

      expect(
        e.toString(),
        equals('TokenProviderException(read): keychain corrupted'),
      );
    });

    test('preserves originalError and stackTrace', () {
      const original = FormatException('bad data');
      final st = StackTrace.current;

      final e = TokenProviderException(
        operation: TokenProviderOperation.clear,
        message: 'wrapped',
        originalError: original,
        stackTrace: st,
      );

      expect(e.originalError, equals(original));
      expect(e.stackTrace, equals(st));
    });

    test('catchable as ApiException', () {
      const exception = TokenProviderException(
        operation: TokenProviderOperation.read,
        message: 'fail',
      );

      expect(() {
        try {
          throw exception;
        } on ApiException catch (e) {
          expect(e, isA<TokenProviderException>());
          rethrow;
        }
      }, throwsA(isA<TokenProviderException>()));
    });
  });
}
