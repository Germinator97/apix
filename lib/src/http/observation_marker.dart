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
