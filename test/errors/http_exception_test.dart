import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('HttpException', () {
    test('extends ApiException', () {
      const exception = HttpException(message: 'Error', statusCode: 500);

      expect(exception, isA<ApiException>());
    });

    test('requires statusCode', () {
      const exception = HttpException(message: 'Error', statusCode: 400);

      expect(exception.statusCode, equals(400));
      expect(exception.message, equals('Error'));
    });

    test('stores responseBody', () {
      const exception = HttpException(
        message: 'Error',
        statusCode: 400,
        responseBody: {'error': 'details'},
      );

      expect(exception.responseBody, equals({'error': 'details'}));
    });

    test('toString includes status code', () {
      const exception = HttpException(message: 'Bad request', statusCode: 400);

      expect(
        exception.toString(),
        equals('HttpException: Bad request (status: 400)'),
      );
    });
  });

  group('ClientException', () {
    test('extends HttpException', () {
      const exception = ClientException(message: 'Error', statusCode: 400);

      expect(exception, isA<HttpException>());
      expect(exception, isA<ApiException>());
    });

    test('toString includes status code', () {
      const exception =
          ClientException(message: 'Bad request', statusCode: 400);

      expect(
        exception.toString(),
        equals('ClientException: Bad request (status: 400)'),
      );
    });
  });

  group('UnauthorizedException', () {
    test('extends ClientException', () {
      const exception = UnauthorizedException();

      expect(exception, isA<ClientException>());
      expect(exception, isA<HttpException>());
      expect(exception, isA<ApiException>());
    });

    test('has default message and status 401', () {
      const exception = UnauthorizedException();

      expect(exception.statusCode, equals(401));
      expect(exception.message, equals('Unauthorized'));
    });

    test('accepts custom message', () {
      const exception = UnauthorizedException(message: 'Token expired');

      expect(exception.message, equals('Token expired'));
      expect(exception.statusCode, equals(401));
    });

    test('toString format', () {
      const exception = UnauthorizedException();

      expect(
        exception.toString(),
        equals('UnauthorizedException: Unauthorized (status: 401)'),
      );
    });
  });

  group('ForbiddenException', () {
    test('extends ClientException', () {
      const exception = ForbiddenException();

      expect(exception, isA<ClientException>());
    });

    test('has default message and status 403', () {
      const exception = ForbiddenException();

      expect(exception.statusCode, equals(403));
      expect(exception.message, equals('Forbidden'));
    });

    test('toString format', () {
      const exception = ForbiddenException(message: 'Access denied');

      expect(
        exception.toString(),
        equals('ForbiddenException: Access denied (status: 403)'),
      );
    });
  });

  group('NotFoundException', () {
    test('extends ClientException', () {
      const exception = NotFoundException();

      expect(exception, isA<ClientException>());
    });

    test('has default message and status 404', () {
      const exception = NotFoundException();

      expect(exception.statusCode, equals(404));
      expect(exception.message, equals('Not Found'));
    });

    test('toString format', () {
      const exception = NotFoundException(message: 'User not found');

      expect(
        exception.toString(),
        equals('NotFoundException: User not found (status: 404)'),
      );
    });
  });

  group('ServerException', () {
    test('extends HttpException', () {
      const exception = ServerException(
        message: 'Internal error',
        statusCode: 500,
      );

      expect(exception, isA<HttpException>());
      expect(exception, isA<ApiException>());
    });

    test('requires statusCode', () {
      const exception = ServerException(
        message: 'Service unavailable',
        statusCode: 503,
      );

      expect(exception.statusCode, equals(503));
    });

    test('toString format', () {
      const exception = ServerException(
        message: 'Internal error',
        statusCode: 500,
      );

      expect(
        exception.toString(),
        equals('ServerException: Internal error (status: 500)'),
      );
    });
  });

  group('Exception hierarchy catch behavior', () {
    test('UnauthorizedException can be caught as ClientException', () {
      Exception? caught;

      try {
        throw const UnauthorizedException();
      } on ClientException catch (e) {
        caught = e;
      }

      expect(caught, isA<UnauthorizedException>());
    });

    test('ClientException can be caught as HttpException', () {
      Exception? caught;

      try {
        throw const ClientException(message: 'Error', statusCode: 400);
      } on HttpException catch (e) {
        caught = e;
      }

      expect(caught, isA<ClientException>());
    });

    test('ServerException can be caught as HttpException', () {
      Exception? caught;

      try {
        throw const ServerException(message: 'Error', statusCode: 500);
      } on HttpException catch (e) {
        caught = e;
      }

      expect(caught, isA<ServerException>());
    });

    test('HttpException can be caught as ApiException', () {
      Exception? caught;

      try {
        throw const HttpException(message: 'Error', statusCode: 400);
      } on ApiException catch (e) {
        caught = e;
      }

      expect(caught, isA<HttpException>());
    });
  });
}
