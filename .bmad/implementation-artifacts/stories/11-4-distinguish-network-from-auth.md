# Story 11.4: Distinguish NetworkException from AuthException in refresh flow

Status: done

## Story

As a developer,
I want refresh requests that fail due to network issues to surface as `NetworkException`, not silently as `AuthException` ("Token refresh failed"),
so that users aren't logged out by transient connectivity blips.

## Context (why)

Today `_performSimplifiedRefresh` (`auth_interceptor.dart:196`) makes a `dio.post` to the refresh endpoint. If that request fails with a connection timeout or DNS error, the exception is caught at `_handleRefresh:182`, `_notifyAuthFailure(e)` is called, the completer completes with `false`, and the original request is rejected with `AuthException('Token refresh failed')` (`auth_interceptor.dart:120`). The user is logged out for what was actually a network blip.

## Acceptance Criteria

1. **Given** the refresh request fails with `DioExceptionType.connectionError`, `connectionTimeout`, `sendTimeout`, or `receiveTimeout`
   **When** `_handleRefresh` catches it
   **Then** the original request is rejected with `NetworkException` (typed appropriately: `ConnectionException` or `TimeoutException`)
   **And** the user is **not** logged out (no `AuthException`)

2. **Given** the refresh request fails with a real auth error (401/403 from refresh endpoint)
   **When** `_handleRefresh` catches it
   **Then** the original request is rejected with `AuthException` (current behavior preserved)
   **And** `onAuthFailure` is invoked

3. **Given** `onAuthFailure(tokenProvider, error)` callback is configured
   **When** the failure is a `NetworkException`
   **Then** `onAuthFailure` is **not** called (not a real auth failure)

4. **Given** the refresh succeeds but `onTokenRefreshed` callback throws a network-related error
   **When** caught in `_handleRefresh`
   **Then** propagated as `NetworkException`, not `AuthException`

## Tasks / Subtasks

- [ ] Task 1: Helper to classify Dio errors
  - [ ] New private function or use `ErrorMapperInterceptor`'s logic
  - [ ] Returns: `ApiException` (already typed) or null

- [ ] Task 2: Update `_handleRefresh` catch block (`auth_interceptor.dart:182`)
  - [ ] Distinguish network errors from auth errors
  - [ ] If network → propagate as `NetworkException` via `handler.reject`, do **not** call `_notifyAuthFailure`
  - [ ] If auth-related (401/403 or anything else) → current behavior

- [ ] Task 3: Update onError flow (`auth_interceptor.dart:114-123`)
  - [ ] Carry the typed exception through, rather than always rejecting with `AuthException`
  - [ ] `_handleRefresh` should return `RefreshResult` (success | networkFailure(error) | authFailure)

- [ ] Task 4: Unit tests
  - [ ] Mock `dio` that fails refresh with `DioExceptionType.connectionError` → verify `ConnectionException` on original request
  - [ ] Mock with `connectionTimeout` → `TimeoutException`
  - [ ] Mock with 401 from refresh → `AuthException` (regression)
  - [ ] Verify `onAuthFailure` not called on network errors
  - [ ] Verify `onAuthFailure` called on real auth failures (regression)

## Dev Notes

### Suggested return type

```dart
sealed class _RefreshOutcome {
  const _RefreshOutcome();
}
final class _RefreshSuccess extends _RefreshOutcome { const _RefreshSuccess(); }
final class _RefreshAuthFailure extends _RefreshOutcome {
  final Object? error;
  const _RefreshAuthFailure(this.error);
}
final class _RefreshNetworkFailure extends _RefreshOutcome {
  final NetworkException error;
  const _RefreshNetworkFailure(this.error);
}
```

`onError` switches on the outcome and rejects accordingly.

### Edge case: refresh endpoint returns 5xx

A 5xx from the refresh endpoint is not a network error per se. Suggested behavior: treat as `AuthException` (refresh truly failed and user needs to re-authenticate when backend recovers). Document this in `AuthConfig`.

### References

- `lib/src/auth/auth_interceptor.dart:114-123,182-189`
- `lib/src/errors/network_exception.dart`
- `lib/src/errors/error_mapper_interceptor.dart` — reuse classification logic

## Dev Agent Record

### File List (Target)

- `lib/src/auth/auth_interceptor.dart` — refactor `_handleRefresh` return shape
- `test/auth/auth_interceptor_test.dart` — new test cases
