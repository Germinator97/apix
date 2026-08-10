import 'package:dio/dio.dart';

import '../http/retry_after.dart';
import 'retry_config.dart';

/// Key used to mark a request as non-retryable.
const String noRetryKey = 'x-no-retry';

/// Key used to force retry of a request whose method is not in
/// [RetryConfig.retryableMethods] (e.g. an idempotency-key-protected POST).
///
/// Overrides the method guard only. It never overrides the no-response
/// (network) guard, the status-code guard, or [RetryConfig.maxAttempts], and
/// [noRetryKey] still takes precedence over it.
const String forceRetryKey = 'x-force-retry';

/// Interceptor that automatically retries failed requests.
///
/// Uses [RetryConfig] to determine retry behavior including
/// maximum attempts, retryable status codes, and backoff delays.
///
/// Example:
/// ```dart
/// final retryInterceptor = RetryInterceptor(
///   config: RetryConfig(maxAttempts: 3),
///   dio: dio,
/// );
/// dio.interceptors.add(retryInterceptor);
/// ```
class RetryInterceptor extends Interceptor {
  /// The retry configuration.
  final RetryConfig config;

  /// The Dio instance for retrying requests.
  final Dio dio;

  /// Creates a [RetryInterceptor] with the given [config] and [dio].
  RetryInterceptor({
    required this.config,
    required this.dio,
  });

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final statusCode = err.response?.statusCode;
      final requestOptions = err.requestOptions;

      // Check if retry is disabled for this request
      if (_isNoRetry(requestOptions)) {
        handler.next(err);
        return;
      }

      // Check if we should retry based on status code.
      // A null status code means no response was received (network error);
      // such requests are never retried, as they may have reached the server.
      if (statusCode == null || !config.shouldRetry(statusCode)) {
        handler.next(err);
        return;
      }

      // Check if the HTTP method is eligible for retry. Non-idempotent methods
      // (POST/PATCH by default) are skipped to avoid duplicating a side effect
      // that may already have been committed before the 5xx. A per-request
      // `forceRetry()` opt-in overrides this guard for provably safe replays
      // (e.g. an idempotency-key-protected POST).
      if (!config.shouldRetryMethod(requestOptions.method) &&
          !_isForceRetry(requestOptions)) {
        handler.next(err);
        return;
      }

      // Get current attempt count
      final currentAttempt = _getAttemptCount(requestOptions);

      // Check if we've exceeded max attempts
      if (currentAttempt >= config.maxAttempts) {
        handler.next(err);
        return;
      }

      // Calculate delay and wait
      final delay = _resolveDelay(err, currentAttempt);
      await Future<void>.delayed(delay);

      // Increment attempt count for the retry
      _setAttemptCount(requestOptions, currentAttempt + 1);

      // Retry the request
      try {
        final response = await dio.fetch<dynamic>(requestOptions);
        handler.resolve(response);
      } on DioException catch (e) {
        // Let the error go through onError again for potential further retries
        handler.next(e);
      }
    } catch (e) {
      handler.next(err);
    }
  }

  /// Resolves the wait duration before the next retry.
  ///
  /// When [RetryConfig.respectRetryAfter] is `true` and the response carries
  /// a `Retry-After` header that we can parse, the parsed value is used
  /// (clamped to `[0, RetryConfig.maxDelayMs]`). Otherwise we fall back to
  /// [RetryConfig.getDelay] (exponential backoff).
  Duration _resolveDelay(DioException err, int currentAttempt) {
    if (config.respectRetryAfter) {
      final header = err.response?.headers.value('retry-after');
      if (header != null) {
        final parsed = _parseRetryAfter(header);
        if (parsed != null) {
          final clampedMs = parsed.inMilliseconds.clamp(0, config.maxDelayMs);
          return Duration(milliseconds: clampedMs);
        }
      }
    }
    return config.getDelay(currentAttempt);
  }

  Duration? _parseRetryAfter(String value) =>
      parseRetryAfter(value, now: DateTime.now());

  /// Parses a `Retry-After` header value (RFC 7231 §7.1.3).
  ///
  /// Supports both delta-seconds (`"60"`) and HTTP-date
  /// (`"Wed, 21 Oct 2026 07:28:00 GMT"`). Returns `null` if the value can't
  /// be parsed. Negative or past values are clamped to [Duration.zero].
  ///
  /// [now] is injectable for deterministic testing of HTTP-date values.
  ///
  /// Delegates to [parseRetryAfterHeader]: the error mapper needs the same
  /// parsing to expose `TooManyRequestsException.retryAfter`, and two copies
  /// would eventually disagree about what the server asked for.
  static Duration? parseRetryAfter(String value, {DateTime? now}) =>
      parseRetryAfterHeader(value, now: now);

  /// Returns true if the request has retry disabled.
  bool _isNoRetry(RequestOptions options) {
    return options.extra[noRetryKey] == true;
  }

  /// Returns true if the request forces retry past the method guard.
  bool _isForceRetry(RequestOptions options) {
    return options.extra[forceRetryKey] == true;
  }

  /// Returns the current attempt count for the request.
  int _getAttemptCount(RequestOptions options) {
    return options.extra['_retryAttempt'] as int? ?? 0;
  }

  /// Sets the attempt count for the request.
  void _setAttemptCount(RequestOptions options, int count) {
    options.extra['_retryAttempt'] = count;
  }
}

/// Extension to easily mark requests as non-retryable.
extension NoRetryExtension on RequestOptions {
  /// Marks this request as non-retryable.
  void disableRetry() {
    extra[noRetryKey] = true;
  }

  /// Returns true if retry is disabled for this request.
  bool get isNoRetry => extra[noRetryKey] == true;

  /// Forces retry of this request even when its HTTP method is not in
  /// [RetryConfig.retryableMethods] (e.g. a `POST`/`PATCH`).
  ///
  /// Use only when the request is provably safe to replay — typically a
  /// non-idempotent request protected by an `Idempotency-Key`. This overrides
  /// the method guard only; the network guard (no response), the status-code
  /// guard, and [RetryConfig.maxAttempts] still apply, and [disableRetry]
  /// still wins if both are set.
  void forceRetry() {
    extra[forceRetryKey] = true;
  }

  /// Returns true if retry is forced past the method guard for this request.
  bool get isForceRetry => extra[forceRetryKey] == true;
}
