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
///
/// ## Where this sits, and why it matters
///
/// `ApiClientFactory` installs it **before the cache interceptor and before
/// every observer**, and both halves of that are load-bearing.
///
/// It used to sit after them, which broke two things at once. The response had
/// already been *stored* by the time the validator saw it, so a business
/// failure dressed as `200 OK` was cached — and a later cache hit resolves from
/// `onRequest`, skipping response interceptors entirely, so that stored failure
/// came back **without being validated at all**, as a success. And
/// `MetricsInterceptor.onResponse` had already recorded the request as
/// `success: true` and released its in-flight entry, so the very failures this
/// feature exists to surface were the ones the dashboards counted as fine.
///
/// Rejections also pass `callFollowingErrorInterceptor: true`, so the failure
/// travels the rest of the error chain — the observers, then
/// `ErrorMapperInterceptor` — instead of ending here.
class ResponseValidatorInterceptor extends Interceptor {
  /// Marks a request whose 2xx body the validator refused.
  ///
  /// Read by `CacheInterceptor.onError`, which must not answer such a rejection
  /// from storage: falling back to a cached body would replace a business
  /// failure the caller needs to see with a stale success.
  static const String validationFailedKey = '_apix_validation_failed';

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
      _refuse(
        handler,
        response,
        ApiException(
          message: 'responseValidator threw: $e',
          statusCode: response.statusCode,
          originalError: e,
          stackTrace: st,
        ),
      );
      return;
    }

    if (exception != null) {
      _refuse(handler, response, exception);
      return;
    }

    handler.next(response);
  }

  /// Rejects [response], keeping [exception] as the error callers will catch.
  ///
  /// The rejection is typed `unknown` rather than `badResponse`, and that is a
  /// decision rather than a detail. `ErrorTrackingInterceptor` filters HTTP
  /// failures through `captureStatusCodes` and always captures everything else.
  /// A validator rejection carries status `200`, so filtering it by status
  /// cannot work — no sane `captureStatusCodes` contains `200`, and one that
  /// did would also capture every successful response. Classing it with the
  /// non-HTTP failures is the only coherent answer: the transport was fine, the
  /// payload was not.
  ///
  /// Consumers who find their business errors too chatty for a tracker filter
  /// them in their own `onError`, which is where that judgement belongs.
  void _refuse(
    ResponseInterceptorHandler handler,
    Response<dynamic> response,
    ApiException exception,
  ) {
    response.requestOptions.extra[validationFailedKey] = true;
    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: exception,
        type: DioExceptionType.unknown,
      ),
      true,
    );
  }
}
