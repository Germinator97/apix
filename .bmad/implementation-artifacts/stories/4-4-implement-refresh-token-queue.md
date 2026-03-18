# Story 4.4: Implement Refresh Token Queue

Status: done

## Story

As a developer,
I want concurrent requests queued during refresh,
so that no race conditions occur.

## Acceptance Criteria

1. **Given** multiple concurrent requests receive a refresh-triggering status code
   **When** refresh is in progress
   **Then** all requests wait in queue (Completer pattern)

2. **Given** refresh succeeds
   **Then** all queued requests retry with new token

3. **Given** refresh fails
   **Then** all queued requests fail with AuthException

## Tasks / Subtasks

- [x] Task 1: Implement Completer-based queue
  - [x] Add _refreshCompleter field to AuthInterceptor
  - [x] isRefreshing getter for queue state
  - [x] _handleRefresh() with Completer coordination

- [x] Task 2: Handle refresh outcomes
  - [x] Success: all waiting requests get new token
  - [x] Failure: reject with AuthException

- [x] Task 3: Create AuthException class
  - [x] Extends ApiException
  - [x] Clear error message for refresh failures

- [x] Task 4: Write unit tests
  - [x] Test concurrent requests share same refresh
  - [x] Test reject with AuthException on failure
  - [x] Test exception handling during refresh

## Dev Notes

### Implementation Pattern

```dart
// Completer coordinates concurrent requests
Completer<bool>? _refreshCompleter;

Future<bool> _handleRefresh() async {
  // If refresh in progress, wait for it
  if (_refreshCompleter != null) {
    return _refreshCompleter!.future;
  }

  // Start new refresh
  _refreshCompleter = Completer<bool>();
  try {
    final success = await config.onRefresh!(config.tokenProvider);
    _refreshCompleter!.complete(success);
    return success;
  } catch (e) {
    _refreshCompleter!.complete(false);
    return false;
  } finally {
    _refreshCompleter = null;
  }
}
```

### References

- [Source: epics.md#Story 4.4]
- [ADR-001: Refresh Token Queue Pattern]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Implemented Completer-based queue for concurrent refresh
- Added isRefreshing getter for state visibility
- Created AuthException for refresh failures
- All waiting requests share same refresh result
- 29 unit tests passing (auth module)

### File List

- `lib/src/auth/auth_interceptor.dart` - Completer queue + AuthException
- `test/auth/auth_interceptor_test.dart` - Queue tests

### Change Log

- 2026-03-16: Story 4.4 implemented - Refresh token queue with Completer
