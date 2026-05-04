# Story 11.2: Respect Retry-After header in RetryInterceptor

Status: done

## Story

As a developer,
I want `RetryInterceptor` to honor the `Retry-After` HTTP header on `429` and `503` responses,
so that my client doesn't hammer rate-limited backends and respects RFC 7231.

## Context (why)

Today `retry_interceptor.dart:65` uses `config.getDelay(currentAttempt)` (exponential backoff) regardless of headers. When a backend explicitly sends `Retry-After: 60`, we still retry after ~1s. This is a real bug for fintech endpoints (an internal app, payment providers) that ban clients ignoring rate limits.

## Acceptance Criteria

1. **Given** a response with `Retry-After: 60` (delta-seconds format)
   **When** retry is triggered
   **Then** the interceptor waits 60 seconds before retrying
   **And** ignores the exponential backoff for this attempt

2. **Given** a response with `Retry-After: Wed, 21 Oct 2026 07:28:00 GMT` (HTTP-date format)
   **When** retry is triggered
   **Then** the delay is computed from `target_date - DateTime.now()`
   **And** clamped to `>= 0`

3. **Given** `Retry-After` value exceeds `RetryConfig.maxDelayMs`
   **When** retry is triggered
   **Then** delay is capped at `maxDelayMs`

4. **Given** `RetryConfig(respectRetryAfter: false)`
   **When** retry is triggered
   **Then** the header is ignored, exponential backoff used

5. **Given** `Retry-After` is malformed or absent
   **When** retry is triggered
   **Then** falls back to exponential backoff (current behavior)

6. **Default** `respectRetryAfter: true`

## Tasks / Subtasks

- [ ] Task 1: Update `RetryConfig`
  - [ ] Add `respectRetryAfter` (bool, default `true`)
  - [ ] Update `copyWith`
  - [ ] Update doc comment

- [ ] Task 2: Update `RetryInterceptor`
  - [ ] Parse `Retry-After` header in `onError` (`retry_interceptor.dart:65`)
  - [ ] Try `int.parse()` first (delta-seconds), then `HttpDate.parse()` for HTTP-date
  - [ ] Cap at `config.maxDelayMs`
  - [ ] If parse fails or header absent → fall back to `config.getDelay(currentAttempt)`

- [ ] Task 3: Unit tests
  - [ ] `429 + Retry-After: 60` → 60s wait
  - [ ] `503 + Retry-After: <future HTTP-date>` → correct delta wait
  - [ ] `Retry-After: 99999` (over cap) → capped to `maxDelayMs`
  - [ ] `Retry-After: garbage` → fallback to exponential
  - [ ] No `Retry-After` → fallback to exponential (regression check)
  - [ ] `respectRetryAfter: false` → always exponential
  - [ ] Past HTTP-date → 0ms wait (immediate retry)

## Dev Notes

### Implementation pattern

```dart
// In retry_interceptor.dart, replace the delay calculation
Duration _resolveDelay(DioException err, int currentAttempt) {
  if (config.respectRetryAfter) {
    final header = err.response?.headers.value('retry-after');
    if (header != null) {
      final parsed = _parseRetryAfter(header);
      if (parsed != null) {
        final clamped = parsed.inMilliseconds.clamp(0, config.maxDelayMs);
        return Duration(milliseconds: clamped);
      }
    }
  }
  return config.getDelay(currentAttempt);
}

Duration? _parseRetryAfter(String value) {
  final seconds = int.tryParse(value.trim());
  if (seconds != null) return Duration(seconds: seconds);
  try {
    final date = HttpDate.parse(value);
    return date.difference(DateTime.now());
  } catch (_) {
    return null;
  }
}
```

`HttpDate.parse` is from `dart:io` — already pulled in transitively via Dio. No new dep.

### References

- RFC 7231 §7.1.3 — Retry-After header definition
- `lib/src/retry/retry_interceptor.dart:65`
- `lib/src/retry/retry_config.dart` — `maxDelayMs` (added in 2.0.0)

## Dev Agent Record

### File List (Target)

- `lib/src/retry/retry_config.dart` — add `respectRetryAfter`
- `lib/src/retry/retry_interceptor.dart` — parse header
- `test/retry/retry_interceptor_test.dart` — new tests
