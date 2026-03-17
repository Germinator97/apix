# Story 5.1: Implement RetryInterceptor

Status: done

## Story

As a developer,
I want failed requests to retry automatically,
so that transient failures are handled transparently.

## Acceptance Criteria

1. **Given** RetryConfig is provided
   **When** a retryable error occurs
   **Then** the request is retried up to maxAttempts times

2. **Given** default configuration
   **Then** maxAttempts is 3

## Tasks / Subtasks

- [x] Task 1: Create RetryConfig class
  - [x] maxAttempts (default: 3)
  - [x] retryStatusCodes (default: [500, 502, 503, 504])
  - [x] baseDelayMs for backoff
  - [x] multiplier for exponential backoff
  - [x] shouldRetry(statusCode) helper
  - [x] getDelay(attempt) calculator

- [x] Task 2: Implement RetryInterceptor
  - [x] Extends Dio Interceptor
  - [x] onError handles retry logic
  - [x] Tracks attempt count via request extras
  - [x] Respects noRetry flag

- [x] Task 3: Write unit tests
  - [x] Test RetryConfig defaults and customization
  - [x] Test exponential backoff calculation
  - [x] Test noRetry flag

## Dev Notes

### Implementation Pattern

```dart
final retryInterceptor = RetryInterceptor(
  config: RetryConfig(
    maxAttempts: 3,
    retryStatusCodes: [500, 502, 503, 504],
    baseDelayMs: 1000,
    multiplier: 2.0,
  ),
  dio: dio,
);

dio.interceptors.add(retryInterceptor);

// Disable retry for specific request
final options = RequestOptions(path: '/critical');
options.disableRetry();
```

### References

- [Source: epics.md#Story 5.1]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- RetryConfig with configurable maxAttempts, status codes, backoff
- RetryInterceptor with automatic retry on configured codes
- noRetryKey and NoRetryExtension for per-request control
- 14 unit tests passing

### File List

- `lib/src/retry/retry_config.dart` - RetryConfig class
- `lib/src/retry/retry_interceptor.dart` - RetryInterceptor + extension
- `test/retry/retry_interceptor_test.dart` - Unit tests

### Change Log

- 2026-03-17: Story 5.1 implemented - RetryInterceptor
