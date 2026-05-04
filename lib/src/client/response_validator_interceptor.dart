import 'package:dio/dio.dart';

import '../errors/api_exception.dart';

/// A callback that inspects a successful (2xx) response and either returns
/// `null` to let it pass through, or returns an [ApiException] subclass to
/// have the request fail with that exception.
///
/// Useful for legacy APIs that signal business errors via 200-OK responses
/// with a payload like `{"success": false, "error": "..."}`.
typedef ResponseValidator = ApiException? Function(
  Response<dynamic> response,
);

/// Interceptor that runs a [ResponseValidator] on every 2xx response.
///
/// When the validator returns a non-null [ApiException], the request is
/// rejected so callers see the same typed exception flow as for HTTP errors.
/// When the validator returns `null`, the response passes through unchanged.
///
/// The validator only fires on `onResponse` (2xx). 4xx/5xx responses go
/// through the existing `ErrorMapperInterceptor` flow.
class ResponseValidatorInterceptor extends Interceptor {
  /// The validator callback.
  final ResponseValidator validator;

  /// Creates a [ResponseValidatorInterceptor] with the given [validator].
  const ResponseValidatorInterceptor(this.validator);

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    ApiException? exception;
    try {
      exception = validator(response);
    } catch (e, st) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: ApiException(
            message: 'responseValidator threw: $e',
            statusCode: response.statusCode,
            originalError: e,
            stackTrace: st,
          ),
          type: DioExceptionType.unknown,
        ),
      );
      return;
    }

    if (exception != null) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: exception,
          type: DioExceptionType.badResponse,
        ),
      );
      return;
    }

    handler.next(response);
  }
}
