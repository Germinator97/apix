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

        test('maps 500 to ServerException', () {
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

          expect(result, isA<ServerException>());
          expect(result, isA<HttpException>());
          expect(result.message, equals('Internal server error'));
          expect(result.statusCode, equals(500));
        });

        // The documented hierarchy promises `on ClientException` /
        // `on ServerException` work. Until these cases existed, every
        // non-401/403/404 status produced a bare HttpException, so both
        // clauses were unreachable at every call site while the README and
        // the doc comments advertised them.
        test('maps unspecialised 4xx to ClientException', () {
          for (final status in [400, 402, 409, 422, 429, 499]) {
            final result = ErrorMapperInterceptor.mapDioException(
              DioException(
                type: DioExceptionType.badResponse,
                requestOptions: RequestOptions(path: '/test'),
                response: Response(
                  statusCode: status,
                  data: {'message': 'nope'},
                  requestOptions: RequestOptions(path: '/test'),
                ),
              ),
            );

            expect(
              result,
              isA<ClientException>(),
              reason: '$status must map to ClientException',
            );
            expect(result.statusCode, equals(status));
          }
        });

        test('maps unspecialised 5xx to ServerException', () {
          for (final status in [500, 501, 502, 503, 504, 599]) {
            final result = ErrorMapperInterceptor.mapDioException(
              DioException(
                type: DioExceptionType.badResponse,
                requestOptions: RequestOptions(path: '/test'),
                response: Response(
                  statusCode: status,
                  data: {'message': 'boom'},
                  requestOptions: RequestOptions(path: '/test'),
                ),
              ),
            );

            expect(
              result,
              isA<ServerException>(),
              reason: '$status must map to ServerException',
            );
            expect(result.statusCode, equals(status));
          }
        });

        test('401/403/404 keep their dedicated subclass', () {
          final cases = <int, Matcher>{
            401: isA<UnauthorizedException>(),
            403: isA<ForbiddenException>(),
            404: isA<NotFoundException>(),
          };

          cases.forEach((status, matcher) {
            final result = ErrorMapperInterceptor.mapDioException(
              DioException(
                type: DioExceptionType.badResponse,
                requestOptions: RequestOptions(path: '/test'),
                response: Response(
                  statusCode: status,
                  data: {'message': 'nope'},
                  requestOptions: RequestOptions(path: '/test'),
                ),
              ),
            );

            expect(result, matcher, reason: 'status $status');
            // They are ClientExceptions too — the category must hold for the
            // specialised ones as well, or `on ClientException` would catch
            // a 400 but miss a 404.
            expect(result, isA<ClientException>(), reason: 'status $status');
          });
        });

        test('stays a bare HttpException when the status is not 4xx/5xx', () {
          // 3xx on the error path, and 0 when no status could be read:
          // labelling either "client" or "server" fault would be a guess.
          for (final status in [null, 302]) {
            final result = ErrorMapperInterceptor.mapDioException(
              DioException(
                type: DioExceptionType.badResponse,
                requestOptions: RequestOptions(path: '/test'),
                response: Response(
                  statusCode: status,
                  requestOptions: RequestOptions(path: '/test'),
                ),
              ),
            );

            expect(result, isA<HttpException>(), reason: 'status $status');
            expect(result, isNot(isA<ClientException>()),
                reason: 'status $status');
            expect(result, isNot(isA<ServerException>()),
                reason: 'status $status');
          }
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
