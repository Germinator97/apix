import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'observer_guard.dart';

/// A performance span opened for a single request.
///
/// Abstracted so the interceptor can be tested without a live Sentry hub, and
/// so a consumer can route spans elsewhere.
abstract class ApiSpan {
  /// Attaches a key/value to the span.
  void setData(String key, Object? value);

  /// Closes the span, optionally recording the HTTP [statusCode] that ended it.
  void finish({int? statusCode});
}

/// Opens a span for a request. Returning null means "don't trace this one".
typedef SpanStarter = ApiSpan? Function(String operation, String description);

/// Configuration for [TracingInterceptor].
class TracingConfig {
  /// Whether tracing is active.
  final bool enabled;

  /// Opens the span. Defaults to a child of Sentry's current transaction.
  ///
  /// When no transaction is in progress, the default returns null and nothing
  /// is traced — a span with no parent would be dropped by Sentry anyway.
  final SpanStarter startSpan;

  /// Creates a [TracingConfig].
  const TracingConfig({
    this.enabled = true,
    this.startSpan = defaultSpanStarter,
  });

  /// Creates a disabled config.
  factory TracingConfig.disabled() => const TracingConfig(enabled: false);

  /// Starts a child of the transaction Sentry currently holds.
  static ApiSpan? defaultSpanStarter(String operation, String description) {
    final parent = Sentry.getSpan();
    if (parent == null) return null;
    return _SentryApiSpan(
      parent.startChild(operation, description: description),
    );
  }
}

/// Interceptor that opens one performance span per network request.
///
/// apix already had both halves of this — `SentrySetup` initialises tracing,
/// `MetricsConfig` measures duration, size and status of every request — but
/// nothing ever created a span. Durations could therefore only land in a
/// breadcrumb: visible *after* an incident, never aggregated. Spotting an
/// endpoint that is merely slow, before it becomes a timeout, meant leaving
/// the tool.
///
/// ## Where this must sit in the chain
///
/// **After the cache interceptor.** When the cache answers from storage it
/// calls `handler.resolve(...)`, which ends the chain without running the
/// following `onResponse` handlers. A span opened before the cache would then
/// never be closed — a leak on exactly the requests that were fastest.
///
/// Sitting after it means a cache hit never reaches this interceptor at all,
/// which is also the honest outcome: a served-from-cache response has no
/// network time to report. `ApiClientFactory` wires this order for you.
class TracingInterceptor extends Interceptor {
  /// The tracing configuration.
  final TracingConfig config;

  /// Creates a [TracingInterceptor].
  TracingInterceptor({TracingConfig? config})
      : config = config ?? const TracingConfig();

  /// Key under which the in-flight span rides on the request.
  static const String _spanKey = '_apix_span';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // A retried request re-enters the chain carrying the same `extra` map, so
    // an unconditional start would open one span per attempt while only the
    // last one ever reached onError — the earlier ones leaking, silently. One
    // span covers the whole logical request instead, which is also what the
    // caller actually waited for: retries and backoff included.
    if (config.enabled && options.extra[_spanKey] == null) {
      // Guarded like every other observation callback: a span starter that
      // throws — no hub, a finished parent, a consumer bug — must not turn a
      // request that would have succeeded into a failure.
      guardObserver(() {
        // The description carries the *path*, never the full URI: query
        // strings routinely carry identifiers, and a span description is not
        // the place to leak one.
        final span = config.startSpan(
          'http.client',
          '${options.method} ${options.uri.path}',
        );
        if (span != null) {
          span.setData('http.request.method', options.method);
          span.setData('server.address', options.uri.host);
          span.setData('url.path', options.uri.path);
          options.extra[_spanKey] = span;
        }
      });
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _finish(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _finish(err.requestOptions, err.response?.statusCode);
    handler.next(err);
  }

  /// Closes the span riding on [options], if any.
  ///
  /// Removes it first: a request replayed by the retry interceptor comes back
  /// through here with the same `extra` map, and finishing a span twice is
  /// how a trace ends up with impossible durations.
  void _finish(RequestOptions options, int? statusCode) {
    final span = options.extra.remove(_spanKey);
    if (span is ApiSpan) {
      guardObserver(() => span.finish(statusCode: statusCode));
    }
  }
}

/// Bridges [ApiSpan] onto a Sentry span.
class _SentryApiSpan implements ApiSpan {
  _SentryApiSpan(this._span);

  final ISentrySpan _span;

  @override
  void setData(String key, Object? value) => _span.setData(key, value);

  @override
  void finish({int? statusCode}) {
    if (statusCode != null) {
      _span.setData('http.response.status_code', statusCode);
      _span.status = SpanStatus.fromHttpStatusCode(statusCode);
    }
    _span.finish();
  }
}
