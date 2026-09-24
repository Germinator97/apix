import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';

/// Reads the delay a response's `Retry-After` asks for, however many times
/// the field was sent.
///
/// Returns the **longest** delay among the values that parse, or `null` when
/// none does. The field is a singleton (RFC 9110 §10.2.3), so a repeat is
/// malformed — but it happens, typically when a gateway and the application
/// behind it both set it. Waiting the longer of two instructions disobeys
/// neither; waiting the shorter may disobey one and earn another `429`.
///
/// It used to be read with `Headers.value`, which throws on a repeated field:
/// the throw escaped the error mapper and the caller received a raw
/// `DioException` instead of a `TooManyRequestsException`.
///
/// Values are not split on commas: an HTTP-date contains one
/// (`Wed, 21 Oct 2026 07:28:00 GMT`).
Duration? retryAfterFrom(Headers? headers, {DateTime? now}) {
  final values = headers?['retry-after'];
  if (values == null) return null;
  Duration? longest;
  for (final value in values) {
    final parsed = parseRetryAfterHeader(value, now: now);
    if (parsed != null && (longest == null || parsed > longest)) {
      longest = parsed;
    }
  }
  return longest;
}

/// Parses a `Retry-After` header value (RFC 7231 §7.1.3).
///
/// Supports both delta-seconds (`"60"`) and HTTP-date
/// (`"Wed, 21 Oct 2026 07:28:00 GMT"`). Returns `null` if the value can't be
/// parsed. Negative or past values are clamped to [Duration.zero].
///
/// [now] is injectable for deterministic testing of HTTP-date values.
///
/// This lives outside both `retry/` and `errors/` because both need it and
/// neither should depend on the other: the retry interceptor uses it to decide
/// how long to wait, and the error mapper uses it to hand the same value to the
/// caller on a `429`. Keeping one implementation is what stops those two from
/// disagreeing about what the server asked for.
Duration? parseRetryAfterHeader(String value, {DateTime? now}) {
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
