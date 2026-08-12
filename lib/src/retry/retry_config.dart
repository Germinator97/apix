import 'dart:math' show Random;

/// Shared generator for jitter, so a const [RetryConfig] can still draw one.
///
/// Not seeded: reproducibility is a test concern, and tests inject their own
/// [Random] through `getDelay(attempt, random: ...)`.
final Random _sharedRandom = Random();

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

  /// Whether to honor the server's `Retry-After` header on retryable responses.
  ///
  /// When `true` (default), the interceptor parses the `Retry-After` header
  /// (delta-seconds or HTTP-date) and uses it as the wait duration for the
  /// next retry, capped at [maxDelayMs]. When `false`, exponential backoff
  /// is always used.
  ///
  /// See RFC 7231 §7.1.3.
  final bool respectRetryAfter;

  /// HTTP methods that are eligible for automatic retry.
  ///
  /// Defaults to the idempotent methods per RFC 7231 §4.2.2:
  /// `{GET, HEAD, OPTIONS, TRACE, PUT, DELETE}`. **`POST` and `PATCH` are
  /// excluded by default** because replaying them is unsafe: a `5xx` returned
  /// *after* the server already committed (e.g. a gateway `502`/`504` timeout
  /// on a payment) would otherwise produce a duplicate (double charge).
  ///
  /// Comparison is case-insensitive; values must be upper-case.
  ///
  /// To retry a specific non-idempotent request that is provably safe to
  /// replay (e.g. a `POST` carrying an `Idempotency-Key`), prefer the
  /// per-request opt-in `RequestOptions.forceRetry()` over widening this set,
  /// which would re-enable retry for *every* request of that method.
  final Set<String> retryableMethods;

  /// Randomness applied to each computed backoff delay, as a fraction of that
  /// delay.
  ///
  /// **Enabled by default (`0.2`, i.e. ±20 %).** Pure exponential backoff is
  /// deterministic: every client that failed during the same outage second
  /// retries at the same instants, so a server coming back up is met with a
  /// synchronised spike at the worst possible moment. Spreading the delays is
  /// what turns that spike back into a curve.
  ///
  /// The default is on because the failure it prevents is a
  /// thundering-herd — it harms whoever *didn't* read the changelog, and an
  /// opt-in would leave every existing consumer exposed.
  ///
  /// A delay of `d` becomes a uniform draw in `[d * (1 - jitter),
  /// d * (1 + jitter)]`, then clamped to `[0, maxDelayMs]`. Set to `0.0` to
  /// restore the previous, strictly deterministic behaviour.
  ///
  /// Must be between `0.0` and `1.0`: above 1.0 the lower bound would go
  /// negative and the delay would collapse to zero for part of the range.
  ///
  /// `Retry-After` is never jittered — when the server names a delay, honouring
  /// it exactly matters more than spreading load.
  final double jitter;

  /// Creates a [RetryConfig] with the given parameters.
  const RetryConfig({
    this.maxAttempts = 3,
    this.retryStatusCodes = const [500, 502, 503, 504],
    this.baseDelayMs = 1000,
    this.multiplier = 2.0,
    this.maxDelayMs = 30000,
    this.respectRetryAfter = true,
    this.jitter = 0.2,
    this.retryableMethods = const {
      'GET',
      'HEAD',
      'OPTIONS',
      'TRACE',
      'PUT',
      'DELETE',
    },
  }) : assert(
          jitter >= 0.0 && jitter <= 1.0,
          'jitter must be within [0.0, 1.0]',
        );

  /// Returns true if the given [statusCode] should trigger a retry.
  bool shouldRetry(int statusCode) => retryStatusCodes.contains(statusCode);

  /// Returns true if the given HTTP [method] is eligible for automatic retry.
  ///
  /// Comparison is case-insensitive.
  bool shouldRetryMethod(String method) =>
      retryableMethods.contains(method.toUpperCase());

  /// Calculates the delay for the given [attempt] number (0-indexed).
  ///
  /// Uses exponential backoff: baseDelayMs * (multiplier ^ attempt), spread by
  /// [jitter], then capped at [maxDelayMs].
  ///
  /// [random] is injectable so tests can pin the draw; production callers omit
  /// it and share a single generator.
  Duration getDelay(int attempt, {Random? random}) {
    final delayMs = baseDelayMs * _pow(multiplier, attempt);
    final spread = _applyJitter(delayMs, random ?? _sharedRandom);
    final capped = spread.clamp(0, maxDelayMs).toInt();
    return Duration(milliseconds: capped);
  }

  /// Spreads [delayMs] uniformly across `±jitter` of itself.
  ///
  /// Clamping happens in [getDelay], after this: jittering a value that was
  /// already capped at [maxDelayMs] could only ever push it back down, which
  /// would quietly bias every capped retry downwards instead of spreading it.
  double _applyJitter(double delayMs, Random random) {
    if (jitter <= 0.0) return delayMs;
    final factor = 1 + (random.nextDouble() * 2 - 1) * jitter;
    return delayMs * factor;
  }

  /// Simple power function, kept to avoid a `pow` call on an int exponent.
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
    bool? respectRetryAfter,
    double? jitter,
    Set<String>? retryableMethods,
  }) {
    return RetryConfig(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      retryStatusCodes: retryStatusCodes ?? this.retryStatusCodes,
      baseDelayMs: baseDelayMs ?? this.baseDelayMs,
      multiplier: multiplier ?? this.multiplier,
      maxDelayMs: maxDelayMs ?? this.maxDelayMs,
      respectRetryAfter: respectRetryAfter ?? this.respectRetryAfter,
      jitter: jitter ?? this.jitter,
      retryableMethods: retryableMethods ?? this.retryableMethods,
    );
  }

  @override
  String toString() {
    return 'RetryConfig(maxAttempts: $maxAttempts, '
        'retryStatusCodes: $retryStatusCodes, '
        'baseDelayMs: $baseDelayMs, '
        'multiplier: $multiplier, '
        'jitter: $jitter, '
        'retryableMethods: $retryableMethods)';
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
          respectRetryAfter == other.respectRetryAfter &&
          jitter == other.jitter &&
          _listEquals(retryStatusCodes, other.retryStatusCodes) &&
          _setEquals(retryableMethods, other.retryableMethods);

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  int get hashCode =>
      maxAttempts.hashCode ^
      baseDelayMs.hashCode ^
      multiplier.hashCode ^
      maxDelayMs.hashCode ^
      respectRetryAfter.hashCode ^
      jitter.hashCode ^
      // Hashed by content, and order-dependently, because `==` compares these
      // element by element. `retryStatusCodes.hashCode` is the *identity* hash
      // of the list, so two configs that compared equal had different hash
      // codes — `{a, b}` kept both, and a `Map<RetryConfig, …>` lost lookups.
      // The trap was seen for the set just below and missed for the list.
      retryStatusCodes.fold<int>(17, (h, code) => h * 31 + code.hashCode) ^
      // Order-independent so two equal sets share a hash code.
      retryableMethods.fold<int>(0, (h, m) => h ^ m.hashCode);
}
