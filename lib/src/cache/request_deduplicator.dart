import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

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
  String generateKey(RequestOptions options) {
    final buffer = StringBuffer()
      ..write(options.method)
      ..write(':')
      ..write(options.uri.toString());

    // Include body hash for requests with body
    if (options.data != null) {
      final bodyHash = _hashBody(options.data);
      buffer.write(':$bodyHash');
    }

    return buffer.toString();
  }

  /// Hashes the request body for deduplication key.
  String _hashBody(dynamic data) {
    String content;
    if (data is String) {
      content = data;
    } else if (data is Map || data is List) {
      content = jsonEncode(data);
    } else {
      content = data.toString();
    }

    final bytes = utf8.encode(content);
    final digest = md5.convert(bytes);
    return digest.toString();
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
