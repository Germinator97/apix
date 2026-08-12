import 'package:dio/dio.dart';

/// Guarantees that one request is observed once per observer, however many
/// times it travels the interceptor chain.
///
/// Deduplication makes a request pass through the error chain twice. The exact
/// mechanism is worth stating, because two plausible explanations are wrong and
/// both were tried first:
///
/// * It is **not** the inner request being observed alongside the outer one.
///   Measured on a cancellation: the inner request never reaches the error
///   chain at all.
/// * It is **not** `handler.reject` replaying the outcome, so marking the outer
///   request inside the deduplicator's `catch` fixed nothing — the outer
///   request is rejected by dio directly, without passing through it.
///
/// What actually happens: the outer and inner requests share a `CancelToken`,
/// so a cancellation rejects them independently, and the *outer* one enters the
/// error chain twice. One network call, two log lines, two tracker events —
/// on a search field cancelling per keystroke, that doubles the noise in the
/// dashboard someone is watching.
///
/// Rather than predicting which pass to suppress, each observer records that it
/// has handled this request and skips the ones after. That is robust to the
/// mechanism: whatever makes a request come round again, it is observed once.
///
/// Marking happens *after* observing, never before — a mark set in advance
/// silences the only pass that was going to report anything, which is precisely
/// what an earlier attempt did (zero events instead of one).
///
/// Lives outside both `cache/` and `observability/`: both ends need it and
/// neither should depend on the other.
class ObservationMarker {
  ObservationMarker._();

  static const String _prefix = '_apix_observed_by_';

  /// Whether [observer] has already handled [options].
  static bool alreadySeen(RequestOptions options, String observer) =>
      options.extra['$_prefix$observer'] == true;

  /// Records that [observer] has handled [options].
  static void markSeen(RequestOptions options, String observer) {
    options.extra['$_prefix$observer'] = true;
  }

  /// Returns true the first time it is called for a given request and observer,
  /// false every time after — the whole contract in one call.
  static bool claim(RequestOptions options, String observer) {
    if (alreadySeen(options, observer)) return false;
    markSeen(options, observer);
    return true;
  }

  /// Key set by `RetryInterceptor` before it replays a request.
  ///
  /// Matched by name rather than imported: this file sits below both `retry/`
  /// and `auth/` precisely so neither depends on the other.
  static const String _retryAttemptKey = '_retryAttempt';

  /// Key set by `AuthInterceptor` before it replays a request post-refresh.
  static const String _authRetryKey = 'apix_is_auth_retry';

  /// Whether [options] is being replayed by apix rather than started fresh.
  ///
  /// True for a `RetryInterceptor` replay and for an `AuthInterceptor` replay
  /// after a token refresh — the two things that re-enter the chain through
  /// `onRequest` carrying the same `extra` map.
  ///
  /// Public because more than one observer needs the same answer, and each
  /// deciding for itself is how they drift: [beginAttempt] uses it to know
  /// whether to clear its marks, and `MetricsInterceptor` uses it to know
  /// whether it is already measuring this request.
  static bool isReplay(RequestOptions options) {
    final extra = options.extra;
    return extra[_retryAttemptKey] != null || extra[_authRetryKey] == true;
  }

  /// Clears the marks at the start of a genuinely new attempt.
  ///
  /// The marks live on `RequestOptions.extra`, which outlives a single
  /// execution: a consumer holding one `RequestOptions` and calling
  /// `dio.fetch(options)` twice found the second failure observed by nobody —
  /// no log, no metric, no tracker event — because the first execution's marks
  /// were still set. An absence, so nothing said so.
  ///
  /// Called from each observer's `onRequest`, which is what makes it precise:
  /// the case the marker exists for — deduplication delivering the *same*
  /// request to the error chain twice — does not re-run `onRequest` in between,
  /// so those marks survive and the second delivery is still skipped.
  ///
  /// **Replays are exempt.** `RetryInterceptor` and `AuthInterceptor` re-enter
  /// the chain through `onRequest`, so clearing there would report a three-try
  /// retry storm as three separate failures. One logical request stays one
  /// event; the attempts are what `RetryConfig`'s `onRetry` callback is for.
  static void beginAttempt(RequestOptions options) {
    if (isReplay(options)) return;
    options.extra.removeWhere((key, _) => key.startsWith(_prefix));
  }
}

/// Identifiers for the interceptors that observe a request.
///
/// Separate keys on purpose: the logger claiming a request must not stop the
/// tracker from seeing it.
abstract final class Observers {
  /// The logging interceptor.
  static const String logger = 'logger';

  /// The error tracking interceptor.
  static const String errorTracking = 'error_tracking';

  /// The metrics interceptor.
  static const String metrics = 'metrics';

  /// The tracing interceptor.
  static const String tracing = 'tracing';
}
