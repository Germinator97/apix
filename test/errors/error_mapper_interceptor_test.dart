import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ErrorMapperInterceptor', () {
    group('mapDioException', () {
      test('maps connectionTimeout to TimeoutException', () {
        final dioError = DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: RequestOptions(
            path: '/test',
            connectTimeout: const Duration(seconds: 30),
          ),
          message: 'Connection timeout',
        );

        final result = ErrorMapperInterceptor.mapDioException(dioError);

        expect(result, isA<TimeoutException>());
        expect(result.message, equals('Connection timeout'));
        expect((result as TimeoutException).duration,
            equals(const Duration(seconds: 30)));
      });

      test('maps sendTimeout to TimeoutException', () {
        final dioError = DioException(
          type: DioExceptionType.sendTimeout,
          requestOptions: RequestOptions(
            path: '/test',
            sendTimeout: const Duration(seconds: 15),
          ),
          message: 'Send timeout',
        );

        final result = ErrorMapperInterceptor.mapDioException(dioError);

        expect(result, isA<TimeoutException>());
        expect(result.message, equals('Send timeout'));
      });

      test('maps receiveTimeout to TimeoutException', () {
        final dioError = DioException(
          type: DioExceptionType.receiveTimeout,
          requestOptions: RequestOptions(
            path: '/test',
            receiveTimeout: const Duration(seconds: 20),
          ),
          message: 'Receive timeout',
        );

        final result = ErrorMapperInterceptor.mapDioException(dioError);

        expect(result, isA<TimeoutException>());
        expect(result.message, equals('Receive timeout'));
      });

      test('maps connectionError to ConnectionException', () {
        final dioError = DioException(
          type: DioExceptionType.connectionError,
          requestOptions: RequestOptions(path: '/test'),
          message: 'Connection failed',
        );

        final result = ErrorMapperInterceptor.mapDioException(dioError);

        expect(result, isA<ConnectionException>());
        expect(result.message, equals('Connection failed'));
      });

      group('badResponse', () {
        test('maps 401 to UnauthorizedException', () {
          final dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 401,
              data: {'message': 'Invalid token'},
              requestOptions: RequestOptions(path: '/test'),
            ),
          );

          final result = ErrorMapperInterceptor.mapDioException(dioError);

          expect(result, isA<UnauthorizedException>());
          expect(result.message, equals('Invalid token'));
          expect(result.statusCode, equals(401));
        });

        test('maps 403 to ForbiddenException', () {
          final dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 403,
              data: {'error': 'Access denied'},
              requestOptions: RequestOptions(path: '/test'),
            ),
          );

          final result = ErrorMapperInterceptor.mapDioException(dioError);

          expect(result, isA<ForbiddenException>());
          expect(result.message, equals('Access denied'));
          expect(result.statusCode, equals(403));
        });

        test('maps 404 to NotFoundException', () {
          final dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 404,
              data: {'detail': 'Resource not found'},
              requestOptions: RequestOptions(path: '/test'),
            ),
          );

          final result = ErrorMapperInterceptor.mapDioException(dioError);

          expect(result, isA<NotFoundException>());
          expect(result.message, equals('Resource not found'));
          expect(result.statusCode, equals(404));
        });

        test('maps 500 to HttpException', () {
          final dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 500,
              data: {'error_description': 'Internal server error'},
              requestOptions: RequestOptions(path: '/test'),
            ),
          );

          final result = ErrorMapperInterceptor.mapDioException(dioError);

          expect(result, isA<HttpException>());
          expect(result.message, equals('Internal server error'));
          expect(result.statusCode, equals(500));
        });

        test('extracts message from various response fields', () {
          // Test 'message' field
          var dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 400,
              data: {'message': 'Bad request message'},
              requestOptions: RequestOptions(path: '/test'),
            ),
          );
          expect(ErrorMapperInterceptor.mapDioException(dioError).message,
              equals('Bad request message'));

          // Test 'error' field
          dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 400,
              data: {'error': 'Error field message'},
              requestOptions: RequestOptions(path: '/test'),
            ),
          );
          expect(ErrorMapperInterceptor.mapDioException(dioError).message,
              equals('Error field message'));

          // Test 'detail' field
          dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 400,
              data: {'detail': 'Detail field message'},
              requestOptions: RequestOptions(path: '/test'),
            ),
          );
          expect(ErrorMapperInterceptor.mapDioException(dioError).message,
              equals('Detail field message'));

          // Test 'error_description' field
          dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 400,
              data: {'error_description': 'Error description message'},
              requestOptions: RequestOptions(path: '/test'),
            ),
          );
          expect(ErrorMapperInterceptor.mapDioException(dioError).message,
              equals('Error description message'));
        });

        test('extracts message from nested error object', () {
          // { "error": { "code": "...", "message": "..." } }
          var dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 401,
              data: {
                'success': false,
                'error': {
                  'code': 'INVALID_CREDENTIALS',
                  'message': 'Email ou mot de passe incorrect.',
                },
                'timestamp': '2026-04-01T13:33:34.678Z',
                'path': '/auth/login',
              },
              requestOptions: RequestOptions(path: '/test'),
            ),
          );
          final result = ErrorMapperInterceptor.mapDioException(dioError);
          expect(result, isA<UnauthorizedException>());
          expect(result.message, equals('Email ou mot de passe incorrect.'));

          // { "error": { "detail": "Not allowed" } }
          dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 403,
              data: {
                'error': {'detail': 'Not allowed'},
              },
              requestOptions: RequestOptions(path: '/test'),
            ),
          );
          expect(ErrorMapperInterceptor.mapDioException(dioError).message,
              equals('Not allowed'));
        });

        test('falls back to HTTP status code when no message field', () {
          final dioError = DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 422,
              data: {'unknown_field': 'some value'},
              requestOptions: RequestOptions(path: '/test'),
            ),
          );

          final result = ErrorMapperInterceptor.mapDioException(dioError);

          expect(result.message, equals('HTTP 422'));
        });
      });

      test('maps cancel to ApiException', () {
        final dioError = DioException(
          type: DioExceptionType.cancel,
          requestOptions: RequestOptions(path: '/test'),
        );

        final result = ErrorMapperInterceptor.mapDioException(dioError);

        expect(result, isA<ApiException>());
        expect(result.message, equals('Request cancelled'));
      });

      test('maps badCertificate to NetworkException', () {
        final dioError = DioException(
          type: DioExceptionType.badCertificate,
          requestOptions: RequestOptions(path: '/test'),
          message: 'Bad certificate',
        );

        final result = ErrorMapperInterceptor.mapDioException(dioError);

        expect(result, isA<NetworkException>());
        expect(result.message, equals('Bad certificate'));
      });

      test('preserves existing ApiException in unknown type', () {
        const existingException = UnauthorizedException(message: 'Existing');
        final dioError = DioException(
          type: DioExceptionType.unknown,
          requestOptions: RequestOptions(path: '/test'),
          error: existingException,
        );

        final result = ErrorMapperInterceptor.mapDioException(dioError);

        expect(result, same(existingException));
      });

      test('maps unknown type to ApiException', () {
        final dioError = DioException(
          type: DioExceptionType.unknown,
          requestOptions: RequestOptions(path: '/test'),
          message: 'Unknown error',
        );

        final result = ErrorMapperInterceptor.mapDioException(dioError);

        expect(result, isA<ApiException>());
        expect(result.message, equals('Unknown error'));
      });
    });
  });
}
