import 'dart:async';

import 'package:dio/dio.dart';

import '../http/body_fingerprint.dart';
import '../http/cache_vary.dart';

/// Deduplicates identical concurrent requests.
///
/// When multiple identical requests are made simultaneously,
/// only one network request is executed and all callers
/// receive the same response.
///
/// Example:
/// ```dart
/// final deduplicator = RequestDeduplicator();
///
/// // These concurrent calls result in only one network request
/// final results = await Future.wait([
///   deduplicator.deduplicate(options, () => dio.fetch(options)),
///   deduplicator.deduplicate(options, () => dio.fetch(options)),
///   deduplicator.deduplicate(options, () => dio.fetch(options)),
/// ]);
/// ```
class RequestDeduplicator {
  /// Creates a deduplicator.
  ///
  /// [varyHeaders] scopes the key to whoever is asking, exactly as it does for
  /// the cache. The window is narrower here — two *concurrent* requests, one
  /// sent before an identity change and one after — but the outcome is the
  /// same one the cache had: the second caller receives the first caller's
  /// body. Collapsing across identities is never what a caller asked for.
  RequestDeduplicator({this.varyHeaders = const []});

  /// Request headers whose value scopes the deduplication key.
  ///
  /// Empty means no scoping, which is the right default for a deduplicator
  /// wired by hand: `ApiClientFactory` threads the configured value in.
  final List<String> varyHeaders;

  final Map<String, _PendingRequest> _pending = {};

  /// Deduplicates the request if an identical one is already in flight.
  ///
  /// Returns the response from the original request if deduplicated,
  /// or executes [execute] if this is the first request.
  Future<Response<dynamic>> deduplicate(
    RequestOptions options,
    Future<Response<dynamic>> Function() execute,
  ) async {
    final key = generateKey(options);

    // Check if there's already a pending request
    if (_pending.containsKey(key)) {
      final pending = _pending[key]!;
      pending.waiterCount++;
      try {
        return await pending.completer.future;
      } finally {
        pending.waiterCount--;
      }
    }

    // This is the first request, execute it
    final completer = Completer<Response<dynamic>>();

    // This completer exists for duplicates that may never arrive, and in the
    // ordinary case none does — so nothing is listening to its future when the
    // request below finishes.
    //
    // That is harmless on success and *not* harmless on failure:
    // `completeError` on a future with no listener reports an unhandled
    // asynchronous error to the current zone. The caller already received that
    // failure through `rethrow`; the zone receives a second, orphaned copy —
    // which in production means an error handler firing, and Sentry filing an
    // exception nobody can act on.
    //
    // The asymmetry is exactly why this survived: only the failure path shows
    // it, and on the GETs deduplication targets, failures are rare — until a
    // `CancelToken` on a search field makes cancellation happen on every
    // keystroke. Reported by a consumer, who measured one unhandled error per
    // cancellation, five for five.
    //
    // `ignore()` registers a listener that discards the outcome, so the future
    // is never orphaned. It does not swallow anything a duplicate is owed:
    // waiters below `await` the same future and each get their own delivery.
    completer.future.ignore();

    _pending[key] = _PendingRequest(completer: completer);

    try {
      final response = await execute();
      completer.complete(response);
      return response;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pending.remove(key);
    }
  }

  /// Generates a unique key for the request based on method, URL, and body.
  ///
  /// Scoped by [varyHeaders] when any are configured — see the constructor.
  String generateKey(RequestOptions options) {
    final buffer = StringBuffer()
      ..write(options.method)
      ..write(':')
      ..write(options.uri.toString());

    // The body, through the same helper the cache key uses. It was a private
    // `_hashBody` here and nothing at all there, which is how `cacheableMethods`
    // could be widened to `POST` and serve one caller another's results. One
    // implementation is what keeps the two keys from disagreeing again.
    final body = bodyFingerprint(options.data);
    if (body != null) buffer.write('|b:$body');

    final vary = varyFingerprint(options, varyHeaders);
    if (vary != null) buffer.write('|v:$vary');

    return buffer.toString();
  }

  /// Returns the number of pending requests.
  int get pendingCount => _pending.length;

  /// Returns true if there's a pending request for the given options.
  bool hasPending(RequestOptions options) {
    final key = generateKey(options);
    return _pending.containsKey(key);
  }

  /// Returns the number of waiters for a given request.
  int getWaiterCount(RequestOptions options) {
    final key = generateKey(options);
    return _pending[key]?.waiterCount ?? 0;
  }

  /// Clears all pending requests (use with caution).
  void clear() {
    _pending.clear();
  }
}

class _PendingRequest {
  final Completer<Response<dynamic>> completer;
  int waiterCount = 0;

  _PendingRequest({required this.completer});
}
