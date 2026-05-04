import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnexpectedContentTypeException', () {
    test('extends ApiException', () {
      const e = UnexpectedContentTypeException(
        expectedContentType: 'application/json',
        actualContentType: 'text/html',
        statusCode: 200,
      );

      expect(e, isA<ApiException>());
      expect(e, isA<Exception>());
    });

    test('exposes expected and actual content types', () {
      const e = UnexpectedContentTypeException(
        expectedContentType: 'application/json',
        actualContentType: 'text/html; charset=utf-8',
        statusCode: 200,
      );

      expect(e.expectedContentType, equals('application/json'));
      expect(e.actualContentType, equals('text/html; charset=utf-8'));
      expect(e.statusCode, equals(200));
    });

    test('handles missing actual content type', () {
      const e = UnexpectedContentTypeException(
        expectedContentType: 'application/json',
        actualContentType: null,
        statusCode: 200,
      );

      expect(e.actualContentType, isNull);
      expect(e.toString(), contains('(none)'));
    });

    test('toString is descriptive', () {
      const e = UnexpectedContentTypeException(
        expectedContentType: 'application/json',
        actualContentType: 'text/html',
        statusCode: 200,
      );

      expect(
        e.toString(),
        equals(
          'UnexpectedContentTypeException: expected application/json, '
          'got text/html (status: 200)',
        ),
      );
    });
  });
}
