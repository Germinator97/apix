import 'dart:convert';
import 'dart:io' show HttpDate;

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

    group('429 rate limiting', () {
      DioException rateLimited({String? retryAfter}) {
        final options = RequestOptions(path: '/test');
        return DioException(
          type: DioExceptionType.badResponse,
          requestOptions: options,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 429,
            data: {'message': 'Slow down'},
            headers: Headers.fromMap({
              if (retryAfter != null) 'retry-after': [retryAfter],
            }),
          ),
        );
      }

      test('maps 429 to TooManyRequestsException', () {
        final result = ErrorMapperInterceptor.mapDioException(rateLimited());

        expect(result, isA<TooManyRequestsException>());
        expect(result.statusCode, equals(429));
      });

      // The whole point of adding a subtype is that it must not narrow what
      // already matched: a consumer catching either of these keeps working.
      test('stays catchable as ClientException and HttpException', () {
        final result = ErrorMapperInterceptor.mapDioException(rateLimited());

        expect(result, isA<ClientException>());
        expect(result, isA<HttpException>());
        expect(result, isA<ApiException>());
      });

      test('exposes retryAfter from a delta-seconds header', () {
        final result = ErrorMapperInterceptor.mapDioException(
          rateLimited(retryAfter: '120'),
        );

        expect(
          (result as TooManyRequestsException).retryAfter,
          equals(const Duration(seconds: 120)),
        );
      });

      test('exposes retryAfter from an HTTP-date header', () {
        final target = DateTime.now().toUtc().add(const Duration(seconds: 90));
        final result = ErrorMapperInterceptor.mapDioException(
          rateLimited(retryAfter: HttpDate.format(target)),
        );

        final retryAfter = (result as TooManyRequestsException).retryAfter;
        expect(retryAfter, isNotNull);
        // Wall-clock moves between formatting and parsing, so assert a window
        // rather than an exact equality that would flake.
        expect(retryAfter!.inSeconds, closeTo(90, 5));
      });

      test('leaves retryAfter null when the header is absent', () {
        final result = ErrorMapperInterceptor.mapDioException(rateLimited());

        expect(
          (result as TooManyRequestsException).retryAfter,
          isNull,
          reason: 'Retry-After is optional — null must read as "unknown '
              'delay", never as "retry now"',
        );
      });

      test('leaves retryAfter null when the header is unparseable', () {
        final result = ErrorMapperInterceptor.mapDioException(
          rateLimited(retryAfter: 'whenever you feel like it'),
        );

        expect((result as TooManyRequestsException).retryAfter, isNull);
      });

      test('carries the application code alongside retryAfter', () {
        final options = RequestOptions(path: '/test');
        final result = ErrorMapperInterceptor.mapDioException(
          DioException(
            type: DioExceptionType.badResponse,
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 429,
              data: {'code': 'RATE_LIMITED', 'message': 'Slow down'},
              headers: Headers.fromMap({
                'retry-after': ['30'],
              }),
            ),
          ),
        );

        expect(result, isA<TooManyRequestsException>());
        expect(result.code, equals('RATE_LIMITED'));
        expect(
          (result as TooManyRequestsException).retryAfter,
          equals(const Duration(seconds: 30)),
        );
      });
    });

    group('application error code', () {
      DioException badResponse(dynamic body, {int statusCode = 400}) {
        final options = RequestOptions(path: '/test');
        return DioException(
          type: DioExceptionType.badResponse,
          requestOptions: options,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: statusCode,
            data: body,
          ),
        );
      }

      test('reads the code from a flat envelope body', () {
        final result = ErrorMapperInterceptor.mapDioException(
          badResponse({
            'code': 'OPERATION_NOT_RETRYABLE',
            'message': 'Cannot retry',
            'data': null,
          }),
        );

        expect(result.code, equals('OPERATION_NOT_RETRYABLE'));
        expect(result.message, equals('Cannot retry'));
      });

      test('reads the code from a nested error object', () {
        final result = ErrorMapperInterceptor.mapDioException(
          badResponse({
            'error': {'code': 'FILE_STORAGE_UNAVAILABLE', 'message': 'Down'},
          }),
        );

        expect(result.code, equals('FILE_STORAGE_UNAVAILABLE'));
      });

      test('stringifies a numeric code so call sites switch on one type', () {
        final result = ErrorMapperInterceptor.mapDioException(
          badResponse({'code': 4001, 'message': 'Numeric'}),
        );

        expect(
          result.code,
          equals('4001'),
          reason: 'a real numeric business code under a different status is '
              'the case this field was built for — the guard must not '
              'take it away',
        );
      });

      // Reported by a consumer: their envelope puts the HTTP status in a
      // field named `code`, so the field meant to free callers from the status
      // handed the status back, disguised as a business code. Nothing signals
      // it — it compiles, it does not throw, and "401" is perfectly plausible.
      group('a code that merely repeats the HTTP status', () {
        test('is dropped rather than reported', () {
          final result = ErrorMapperInterceptor.mapDioException(
            badResponse(
              {
                'code': 401,
                'status': 'error',
                'message': 'Authentification requise.',
              },
              statusCode: 401,
            ),
          );

          expect(
            result.code,
            isNull,
            reason: 'reporting it would restore the coupling to the status '
                'that this field exists to remove',
          );
          expect(result.statusCode, equals(401), reason: 'still available');
          expect(result.message, equals('Authentification requise.'));
        });

        test('is dropped when spelled as a string too', () {
          final result = ErrorMapperInterceptor.mapDioException(
            badResponse({'code': '404', 'message': 'Introuvable'},
                statusCode: 404),
          );

          expect(
            result.code,
            isNull,
            reason: 'the numeric spelling is not the only one an envelope uses',
          );
        });

        test('leaves a genuine code that differs from the status', () {
          for (final body in [
            {'code': 4001},
            {'code': 'INSUFFICIENT_FUNDS'},
            {'code': '4010'},
          ]) {
            final result = ErrorMapperInterceptor.mapDioException(
              badResponse(body, statusCode: 401),
            );

            expect(
              result.code,
              isNotNull,
              reason: '$body was dropped — the guard is cutting too wide',
            );
          }
        });

        test('applies to the nested shape as well', () {
          final result = ErrorMapperInterceptor.mapDioException(
            badResponse({
              'error': {'code': 403, 'message': 'Interdit'},
            }, statusCode: 403),
          );

          expect(result.code, isNull);
        });
      });

      test('honours a custom errorCodeKey', () {
        final result = ErrorMapperInterceptor.mapDioException(
          badResponse({'error_code': 'LEGACY_KEY', 'message': 'Custom'}),
          errorCodeKey: 'error_code',
        );

        expect(result.code, equals('LEGACY_KEY'));
      });

      // Asserting through `mapDioException(..., errorCodeKey: i.errorCodeKey)`
      // would be circular — expectation and measurement would both come from
      // the same field. Going through the factory proves the whole chain
      // instead: `ApiClientConfig.errorCodeKey` reaches the mapper, and what
      // the caller catches carries the code.
      test('the configured key reaches the caller through the factory',
          () async {
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.test',
          errorCodeKey: 'error_code',
          httpClientAdapter: _ErrorBodyAdapter({'error_code': 'WIRED'}),
        );

        await expectLater(
          client.get<dynamic>('/test'),
          throwsA(isA<ClientException>()
              .having((e) => e.code, 'code', 'WIRED')
              .having((e) => e.statusCode, 'statusCode', 400)),
        );
      });

      test('the default key leaves a differently-keyed body null', () async {
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.test',
          httpClientAdapter: _ErrorBodyAdapter({'error_code': 'WIRED'}),
        );

        await expectLater(
          client.get<dynamic>('/test'),
          throwsA(isA<ClientException>().having((e) => e.code, 'code', isNull)),
          reason: 'without this, the previous test would pass even if the '
              'mapper ignored its key and read every field',
        );
      });

      // The absent-code cases matter as much as the present ones: `code` is
      // read defensively, so a bug that returned a plausible-looking value for
      // a malformed body would never raise anything.
      test('yields null when the body carries no code', () {
        final result = ErrorMapperInterceptor.mapDioException(
          badResponse({'message': 'No code here'}),
        );

        expect(result.code, isNull);
      });

      test('yields null when the body is not a JSON object', () {
        expect(
          ErrorMapperInterceptor.mapDioException(badResponse('plain text'))
              .code,
          isNull,
        );
        expect(
          ErrorMapperInterceptor.mapDioException(badResponse(null)).code,
          isNull,
        );
        expect(
          ErrorMapperInterceptor.mapDioException(badResponse([1, 2, 3])).code,
          isNull,
        );
      });

      test('yields null when the code is neither a string nor a number', () {
        final result = ErrorMapperInterceptor.mapDioException(
          badResponse({
            'code': {'nested': 'object'},
          }),
        );

        expect(
          result.code,
          isNull,
          reason: 'a toString() here would turn a malformed body into a '
              'plausible-looking code',
        );
      });

      test('is null on non-HTTP failures, which have no body to read', () {
        final result = ErrorMapperInterceptor.mapDioException(
          DioException(
            type: DioExceptionType.connectionError,
            requestOptions: RequestOptions(path: '/test'),
            message: 'Offline',
          ),
        );

        expect(result.code, isNull);
      });

      test('is carried by every mapped status, not just the named ones', () {
        for (final status in [401, 403, 404, 422, 500, 503]) {
          final result = ErrorMapperInterceptor.mapDioException(
            badResponse({'code': 'CODE_$status'}, statusCode: status),
          );

          expect(
            result.code,
            equals('CODE_$status'),
            reason: 'status $status dropped the application code',
          );
        }
      });
    });
  });
}

/// Answers a fixed 400 with [body], so the error path can be exercised through
/// a real Dio chain rather than by calling the mapper directly.
class _ErrorBodyAdapter implements HttpClientAdapter {
  _ErrorBodyAdapter(this.body);

  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      400,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
