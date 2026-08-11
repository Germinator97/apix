import 'dart:async';

/// Runs a consumer-supplied observation callback without letting it affect the
/// request it observes.
///
/// Logging, metrics, breadcrumbs, spans and error capture are all *side*
/// channels: a request that succeeded must still succeed when the analytics
/// backend is down, and a request that failed must fail with its own error,
/// not with the tracker's.
///
/// Before this existed, none of that held. A `logHandler`, an `onMetrics`, an
/// `onBreadcrumb` or a span starter that threw turned a perfectly good `200`
/// into an `ApiException` — measured, not assumed. The one place that got it
/// right was `RetryInterceptor.onRetry`, which carried its own try/catch; this
/// generalises that guard rather than repeating it five times.
///
/// Failures are swallowed on purpose and cannot be reported anywhere: the only
/// channel available for reporting *is* the one that just failed. Trying would
/// risk a loop — a broken tracker producing an error routed to the same broken
/// tracker.
void guardObserver(void Function() body) {
  try {
    body();
  } catch (_) {
    // Observability must never break the path it observes.
  }
}

/// Same contract for a callback that returns a `Future`.
///
/// Two distinct failures have to be caught here, and missing either one is
/// enough to leak:
///
/// * a **synchronous** throw, before the future is even created;
/// * an **asynchronous** rejection, which is the subtler one. A `Future`
///   returned and then dropped is not merely ignored: when it rejects with no
///   listener attached, Dart reports an unhandled asynchronous error to the
///   current zone. That is precisely the defect a consumer reported in
///   `RequestDeduplicator` — and `ErrorTrackingConfig.onError` had exactly the
///   same shape, so a tracker that failed asynchronously produced an error
///   nobody could receive, from inside the component whose job is receiving
///   errors.
void guardAsyncObserver(Future<void> Function() body) {
  try {
    unawaited(body().catchError((Object _) {}));
  } catch (_) {
    // Threw before returning a future.
  }
}
