import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ParsingException', () {
    test('creates with required message', () {
      const exception = ParsingException(message: 'Bad payload');

      expect(exception.message, equals('Bad payload'));
      expect(exception.statusCode, isNull);
      expect(exception.originalError, isNull);
      expect(exception.stackTrace, isNull);
    });

    test('creates with all properties', () {
      const original = FormatException('Unexpected end of input');
      final stack = StackTrace.current;

      final exception = ParsingException(
        message: 'Bad payload',
        statusCode: 200,
        originalError: original,
        stackTrace: stack,
      );

      expect(exception.message, equals('Bad payload'));
      expect(exception.statusCode, equals(200));
      expect(exception.originalError, equals(original));
      expect(exception.stackTrace, equals(stack));
    });

    test('extends ApiException', () {
      const exception = ParsingException(message: 'x');

      expect(exception, isA<ApiException>());
      expect(exception, isA<Exception>());
    });

    test('toString without status code', () {
      const exception = ParsingException(message: 'Bad payload');

      expect(exception.toString(), equals('ParsingException: Bad payload'));
    });

    test('toString with status code', () {
      const exception =
          ParsingException(message: 'Bad payload', statusCode: 200);

      expect(
        exception.toString(),
        equals('ParsingException: Bad payload (status: 200)'),
      );
    });

    test('catchable as ApiException', () {
      const exception = ParsingException(message: 'x');

      expect(() {
        try {
          throw exception;
        } on ApiException catch (e) {
          expect(e, isA<ParsingException>());
          rethrow;
        }
      }, throwsA(isA<ParsingException>()));
    });
  });
}
