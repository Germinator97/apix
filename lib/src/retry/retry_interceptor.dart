import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';

import 'retry_config.dart';

/// Key used to mark a request as non-retryable.
const String noRetryKey = 'x-no-retry';

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

      // Check if we should retry based on status code
      if (statusCode == null || !config.shouldRetry(statusCode)) {
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
  static Duration? parseRetryAfter(String value, {DateTime? now}) {
    final trimmed = value.trim();
    final seconds = int.tryParse(trimmed);
    if (seconds != null) {
      return Duration(seconds: seconds < 0 ? 0 : seconds);
    }
    try {
      final target = HttpDate.parse(trimmed);
      final delta = target.difference(now ?? DateTime.now());
      return delta.isNegative ? Duration.zero : delta;
    } catch (_) {
      return null;
    }
  }

  /// Returns true if the request has retry disabled.
  bool _isNoRetry(RequestOptions options) {
    return options.extra[noRetryKey] == true;
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
}
