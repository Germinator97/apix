import 'package:dio/dio.dart';

/// Reads a response header without ever throwing on a repeated field.
///
/// dio's `Headers.value` throws as soon as a field carries more than one
/// value — and a repeat is not rare: a gateway and the application behind it
/// both set `Retry-After`, two layers each add their `Cache-Control`. Called
/// from an interceptor, that throw escaped as an untyped `DioException` and
/// replaced the response it was reading: a `429` stopped being a
/// `TooManyRequestsException` because its header was sent twice.
///
/// HTTP has two kinds of field (RFC 9110 §5.3), hence two readers:
///
/// - [joinedHeaderValue] for list-based fields such as `Cache-Control`, whose
///   repeated lines combine into one comma-separated value;
/// - [firstHeaderValue] for singleton fields such as `Content-Type` or
///   `ETag`, where a repeat is malformed and the first line wins — which is
///   also what dio's own transformer reads.
///
/// `Retry-After` is a singleton too, but its repeats are resolved by value
/// rather than by position: see `retryAfterFrom`.
String? firstHeaderValue(Headers? headers, String name) {
  final values = headers?[name];
  if (values == null || values.isEmpty) return null;
  return values.first;
}

/// Reads a list-based header field, its repeated lines joined by `", "`.
///
/// See [firstHeaderValue] for why neither reader calls `Headers.value`.
String? joinedHeaderValue(Headers? headers, String name) {
  final values = headers?[name];
  if (values == null || values.isEmpty) return null;
  return values.join(', ');
}
