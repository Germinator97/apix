import 'package:dio/dio.dart';

import '../http/retry_after.dart';
import 'api_exception.dart';
import 'http_exception.dart';
import 'network_exception.dart';

/// Interceptor that transforms [DioException] into typed [ApiException].
///
/// This interceptor ensures that all errors thrown by the API client
/// are properly typed [ApiException] subclasses, making error handling
/// predictable and type-safe.
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users');
/// } on UnauthorizedException catch (e) {
///   // Handle 401
/// } on TimeoutException catch (e) {
///   // Handle timeout
/// } on ApiException catch (e) {
///   // Handle other API errors
/// }
/// ```
class ErrorMapperInterceptor extends Interceptor {
  /// Default body key read for the application-level error code.
  static const String defaultErrorCodeKey = 'code';

  /// Body key holding the application-level error code.
  ///
  /// Mirrors `ApiClientConfig.errorCodeKey`, which is what
  /// `ApiClientFactory` threads in here. See [ApiException.code].
  final String errorCodeKey;

  /// Creates an [ErrorMapperInterceptor].
  const ErrorMapperInterceptor({this.errorCodeKey = defaultErrorCodeKey});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final apiException = mapDioException(err, errorCodeKey: errorCodeKey);

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: apiException,
        stackTrace: err.stackTrace,
      ),
    );
  }

  /// Maps a [DioException] to the appropriate [ApiException] subtype.
  ///
  /// [errorCodeKey] names the body field carrying the application-level error
  /// code (see [ApiException.code]). It is a parameter rather than read off an
  /// instance because this is also called statically from
  /// `ErrorTrackingInterceptor`, which sits earlier in the chain and holds no
  /// reference to the mapper's configuration.
  static ApiException mapDioException(
    DioException err, {
    String errorCodeKey = defaultErrorCodeKey,
  }) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
        return TimeoutException(
          message: err.message ?? 'Connection timeout',
          duration: err.requestOptions.connectTimeout,
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.sendTimeout:
        return TimeoutException(
          message: err.message ?? 'Send timeout',
          duration: err.requestOptions.sendTimeout,
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.receiveTimeout:
        return TimeoutException(
          message: err.message ?? 'Receive timeout',
          duration: err.requestOptions.receiveTimeout,
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.connectionError:
        return ConnectionException(
          message: err.message ?? 'Connection failed',
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.badResponse:
        return _mapBadResponse(err, errorCodeKey);

      case DioExceptionType.cancel:
        return ApiException(
          message: 'Request cancelled',
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.badCertificate:
        return NetworkException(
          message: err.message ?? 'Bad certificate',
          originalError: err,
          stackTrace: err.stackTrace,
        );

      // `unknown`, `transformTimeout` (added in dio 5.10.0) and any future
      // DioExceptionType land here. apix supports dio >=5.4.0, so newer enum
      // values cannot be matched by name without breaking the lower bound; a
      // named `unknown` case is intentionally omitted so this default stays
      // reachable on older dio where every value is otherwise covered.
      default:
        // Check if the inner error is already an ApiException
        if (err.error is ApiException) {
          return err.error as ApiException;
        }
        return ApiException(
          message: err.message ?? 'Unknown error',
          originalError: err.error ?? err,
          stackTrace: err.stackTrace,
        );
    }
  }

  static ApiException _mapBadResponse(DioException err, String errorCodeKey) {
    final response = err.response;
    final statusCode = response?.statusCode ?? 0;
    final message = _extractMessage(response);
    final code = _extractCode(response, errorCodeKey, statusCode);

    return switch (statusCode) {
      401 => UnauthorizedException(
          message: message,
          responseBody: response?.data,
          code: code,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
      403 => ForbiddenException(
          message: message,
          responseBody: response?.data,
          code: code,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
      404 => NotFoundException(
          message: message,
          responseBody: response?.data,
          code: code,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
      // Must precede the generic 4xx arm below, which would otherwise swallow
      // 429 into a plain ClientException and drop the one thing that makes a
      // rate-limit actionable: how long to wait.
      429 => TooManyRequestsException(
          message: message,
          retryAfter: _extractRetryAfter(response),
          responseBody: response?.data,
          code: code,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
      // 4xx / 5xx that have no dedicated subclass still get the right
      // *category*, so `on ClientException` / `on ServerException` fire as the
      // documented hierarchy promises. Before this, every non-401/403/404
      // status fell through to a bare HttpException and those two clauses were
      // dead code at every call site.
      _ when statusCode >= 400 && statusCode < 500 => ClientException(
          message: message,
          statusCode: statusCode,
          responseBody: response?.data,
          code: code,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
      _ when statusCode >= 500 && statusCode < 600 => ServerException(
          message: message,
          statusCode: statusCode,
          responseBody: response?.data,
          code: code,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
      // Anything else — 1xx/2xx/3xx reaching the error path, or 0 when no
      // status could be read — stays a bare HttpException: claiming "client"
      // or "server" fault there would be a guess.
      _ => HttpException(
          message: message,
          statusCode: statusCode,
          responseBody: response?.data,
          code: code,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
    };
  }

  /// Reads and parses the `Retry-After` header, if the response carried one.
  ///
  /// Uses the same parser as `RetryInterceptor`, so what the caller is told to
  /// wait and what the interceptor actually waits cannot drift apart.
  static Duration? _extractRetryAfter(Response<dynamic>? response) {
    final header = response?.headers.value('retry-after');
    return header == null ? null : parseRetryAfterHeader(header);
  }

  /// Reads the application-level error code from the response body.
  ///
  /// Looks in the same two shapes [_extractMessage] already handles — flat
  /// (`{"code": "..."}`) then nested (`{"error": {"code": "..."}}`) — so a
  /// backend does not have to place its code and its message differently for
  /// both to be picked up.
  ///
  /// A numeric code is stringified: a JSON `4001` comes back as `'4001'`, so
  /// call sites can `switch` on a single type without knowing which of the two
  /// the server sent. Any other type yields null rather than a `toString()`
  /// that would turn a malformed body into a plausible-looking code.
  ///
  /// **A value equal to [statusCode] is discarded**, whatever its type. Plenty
  /// of envelopes put the HTTP status in a field literally named `code`:
  ///
  /// ```json
  /// {"code": 401, "status": "error", "message": "Authentification requise."}
  /// ```
  ///
  /// Read as-is, `ApiException.code` would be `'401'` — and this field exists
  /// precisely to free callers from branching on the status. Handing it back
  /// under another name would restore that coupling *in disguise*: a
  /// `switch (e.code)` looks like business logic while it keys on a status that
  /// can drift between server revisions. Nothing would signal it either, since
  /// the value is perfectly plausible.
  ///
  /// The guard is deliberately narrow. Refusing every numeric code — the first
  /// remedy suggested — would also drop the legitimate case (`4001` under a
  /// `400`), which is the one this field was built for. Equality with the
  /// status is the only mechanically detectable signal, and it costs one real
  /// case: an API whose genuine business code happens to equal its own status.
  /// That case is indistinguishable from the disguise by construction.
  ///
  /// Reported by a consumer, against the field these codes are read from.
  static String? _extractCode(
    Response<dynamic>? response,
    String key,
    int statusCode,
  ) {
    final data = response?.data;
    if (data is! Map) return null;

    final nested = data['error'];
    final code = data[key] ?? (nested is Map ? nested[key] : null);

    final normalised = switch (code) {
      final String value => value,
      final num value => value.toString(),
      _ => null,
    };

    // Compared after normalising, so `"401"` as a string is caught too — the
    // reported remedy only covered the numeric spelling.
    return normalised == statusCode.toString() ? null : normalised;
  }

  static String _extractMessage(Response<dynamic>? response) {
    final data = response?.data;

    if (data is Map) {
      // Common API message field names (flat structure)
      final message =
          data['message'] ?? data['detail'] ?? data['error_description'];

      if (message is String) {
        return message;
      }

      // Nested error object: { "error": { "message": "..." } }
      final error = data['error'];
      if (error is Map) {
        final nestedMessage =
            error['message'] ?? error['detail'] ?? error['description'];
        if (nestedMessage is String) {
          return nestedMessage;
        }
      }

      // Flat error string: { "error": "Something went wrong" }
      if (error is String) {
        return error;
      }
    }

    return 'HTTP ${response?.statusCode ?? 'error'}';
  }
}
