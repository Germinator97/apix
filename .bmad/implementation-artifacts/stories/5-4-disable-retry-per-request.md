# Story 5.4: Disable Retry Per Request

Status: done

## Story

As a developer,
I want to disable retry for specific requests,
so that I control critical operations.

## Acceptance Criteria

1. **Given** a request with noRetry option
   **When** an error occurs
   **Then** no retry is attempted

2. **Given** noRetry is set
   **Then** the error is thrown immediately

## Tasks / Subtasks

- [x] Task 1: Implemented in Story 5-1
  - [x] noRetryKey constant
  - [x] NoRetryExtension with disableRetry()
  - [x] isNoRetry getter
  - [x] _isNoRetry() check in onError
  - [x] Unit tests

## Dev Notes

### Implementation (from Story 5-1)

```dart
// Disable retry for critical request
final options = RequestOptions(path: '/payment/charge');
options.disableRetry();

// Or check status
if (options.isNoRetry) {
  // Retry is disabled
}

// In Dio request
dio.post(
  '/payment/charge',
  options: Options(extra: {noRetryKey: true}),
);
```

### References

- [Source: epics.md#Story 5.4]
- Implemented as part of Story 5.1

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- Functionality delivered in Story 5-1
- noRetryKey and NoRetryExtension available
- Tests verify noRetry flag is respected

### File List

- `lib/src/retry/retry_interceptor.dart` - noRetryKey + extension
- `test/retry/retry_interceptor_test.dart` - noRetry tests

### Change Log

- 2026-03-17: Story 5.4 marked done - Already implemented in 5-1
