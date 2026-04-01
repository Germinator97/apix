/// Configuration for retry behavior.
///
/// Defines how failed requests should be retried, including
/// the maximum number of attempts and which status codes trigger retry.
///
/// Example:
/// ```dart
/// final config = RetryConfig(
///   maxAttempts: 3,
///   retryStatusCodes: [500, 502, 503, 504],
/// );
/// ```
class RetryConfig {
  /// Maximum number of retry attempts.
  ///
  /// Defaults to 3. The total number of requests made will be
  /// maxAttempts + 1 (the initial request plus retries).
  final int maxAttempts;

  /// HTTP status codes that should trigger a retry.
  ///
  /// Defaults to `[500, 502, 503, 504]` (common server errors).
  final List<int> retryStatusCodes;

  /// Base delay between retry attempts in milliseconds.
  ///
  /// Used for exponential backoff calculation.
  /// Defaults to 1000ms (1 second).
  final int baseDelayMs;

  /// Multiplier for exponential backoff.
  ///
  /// Each subsequent retry waits baseDelayMs * (multiplier ^ attemptNumber).
  /// Defaults to 2.0.
  final double multiplier;

  /// Maximum delay between retries in milliseconds.
  ///
  /// Caps the exponential backoff to prevent excessively long waits.
  /// Defaults to 30000ms (30 seconds).
  final int maxDelayMs;

  /// Creates a [RetryConfig] with the given parameters.
  const RetryConfig({
    this.maxAttempts = 3,
    this.retryStatusCodes = const [500, 502, 503, 504],
    this.baseDelayMs = 1000,
    this.multiplier = 2.0,
    this.maxDelayMs = 30000,
  });

  /// Returns true if the given [statusCode] should trigger a retry.
  bool shouldRetry(int statusCode) => retryStatusCodes.contains(statusCode);

  /// Calculates the delay for the given [attempt] number (0-indexed).
  ///
  /// Uses exponential backoff: baseDelayMs * (multiplier ^ attempt),
  /// capped at [maxDelayMs].
  Duration getDelay(int attempt) {
    final delayMs = baseDelayMs * _pow(multiplier, attempt);
    final capped = delayMs.clamp(0, maxDelayMs).toInt();
    return Duration(milliseconds: capped);
  }

  /// Simple power function to avoid importing dart:math.
  double _pow(double base, int exponent) {
    if (exponent == 0) return 1.0;
    var result = base;
    for (var i = 1; i < exponent; i++) {
      result *= base;
    }
    return result;
  }

  /// Creates a copy with the given fields replaced.
  RetryConfig copyWith({
    int? maxAttempts,
    List<int>? retryStatusCodes,
    int? baseDelayMs,
    double? multiplier,
    int? maxDelayMs,
  }) {
    return RetryConfig(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      retryStatusCodes: retryStatusCodes ?? this.retryStatusCodes,
      baseDelayMs: baseDelayMs ?? this.baseDelayMs,
      multiplier: multiplier ?? this.multiplier,
      maxDelayMs: maxDelayMs ?? this.maxDelayMs,
    );
  }

  @override
  String toString() {
    return 'RetryConfig(maxAttempts: $maxAttempts, '
        'retryStatusCodes: $retryStatusCodes, '
        'baseDelayMs: $baseDelayMs, '
        'multiplier: $multiplier)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetryConfig &&
          runtimeType == other.runtimeType &&
          maxAttempts == other.maxAttempts &&
          baseDelayMs == other.baseDelayMs &&
          multiplier == other.multiplier &&
          maxDelayMs == other.maxDelayMs &&
          _listEquals(retryStatusCodes, other.retryStatusCodes);

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      maxAttempts.hashCode ^
      baseDelayMs.hashCode ^
      multiplier.hashCode ^
      maxDelayMs.hashCode ^
      retryStatusCodes.hashCode;
}
