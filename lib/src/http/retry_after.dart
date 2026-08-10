import 'dart:io' show HttpDate;

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
