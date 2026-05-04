# Story 11.3: Add TokenProviderException for token retrieval errors

Status: done

## Story

As a developer,
I want `TokenProvider` failures wrapped in a typed `TokenProviderException` instead of leaking raw exceptions,
so that I can distinguish storage/keychain errors from network errors and handle them deliberately.

## Context (why)

If `tokenProvider.getAccessToken()` throws (e.g. `PlatformException` from a corrupted keychain on iOS, or a custom `TokenProvider` that throws), the exception is wrapped in a generic `DioException(error: e)` (`auth_interceptor.dart:69-75`), which `_execute` may not unwrap as `ApiException`. The user sees an opaque crash. The Germinator standard *"Re-wrapping d'exception qui perd de l'information"* (CLAUDE.md anti-patterns) is also violated: type info is lost.

## Acceptance Criteria

1. **Given** `tokenProvider.getAccessToken()` throws
   **When** `AuthInterceptor.onRequest` runs
   **Then** the request is rejected with `TokenProviderException` (subclass of `ApiException`)
   **And** `originalError` and `stackTrace` are preserved

2. **Given** `tokenProvider.getRefreshToken()` throws inside `_performSimplifiedRefresh`
   **When** refresh is triggered
   **Then** propagated as `TokenProviderException` (not silent `false`)

3. **Given** `tokenProvider.saveTokens()` throws inside the user's `onTokenRefreshed` callback
   **When** refresh succeeds but persistence fails
   **Then** the failure surfaces as `TokenProviderException` (not silent success)

4. **Given** `TokenProviderException`
   **Then** it extends `ApiException`
   **And** `message` includes which operation failed: `'Token retrieval failed'` / `'Token persistence failed'`

5. **Given** existing callers using `on ApiException catch`
   **Then** they catch the new exception transparently

## Tasks / Subtasks

- [ ] Task 1: Create `TokenProviderException`
  - [ ] New file `lib/src/auth/token_provider_exception.dart`
  - [ ] Extends `ApiException`
  - [ ] Optional `operation` field (`read` | `write` | `clear`)

- [ ] Task 2: Wrap calls in `AuthInterceptor`
  - [ ] `auth_interceptor.dart:61` — wrap `getAccessToken()` in try/catch
  - [ ] `auth_interceptor.dart:197` — wrap `getRefreshToken()` similarly
  - [ ] `auth_interceptor.dart:212` — `onTokenRefreshed` callback throws → `TokenProviderException(operation: write)`
  - [ ] Reject `DioException(error: tokenException)` so `_execute` unwraps it

- [ ] Task 3: Export and document
  - [ ] Add export in `lib/apix.dart`
  - [ ] Document in README under "Error hierarchy"

- [ ] Task 4: Unit tests
  - [ ] Mock `TokenProvider` that throws on `getAccessToken` → verify `TokenProviderException`
  - [ ] Same for `getRefreshToken` during refresh flow
  - [ ] `onTokenRefreshed` user callback throws → verify `TokenProviderException(operation: write)`
  - [ ] Hierarchy: `on ApiException catch` catches it

## Dev Notes

### Implementation pattern

```dart
// lib/src/auth/token_provider_exception.dart
enum TokenProviderOperation { read, write, clear }

class TokenProviderException extends ApiException {
  final TokenProviderOperation operation;

  const TokenProviderException({
    required this.operation,
    required super.message,
    super.originalError,
    super.stackTrace,
  });
}

// In auth_interceptor.dart onRequest
try {
  token = await config.tokenProvider.getAccessToken();
} catch (e, st) {
  handler.reject(DioException(
    requestOptions: options,
    error: TokenProviderException(
      operation: TokenProviderOperation.read,
      message: 'Token retrieval failed: $e',
      originalError: e,
      stackTrace: st,
    ),
    type: DioExceptionType.unknown,
  ));
  return;
}
```

### References

- CLAUDE.md anti-patterns: *"Re-wrapping d'exception qui perd de l'information"*
- `lib/src/auth/auth_interceptor.dart:61,197,212`

## Dev Agent Record

### File List (Target)

- `lib/src/auth/token_provider_exception.dart` — new
- `lib/src/auth/auth_interceptor.dart` — wrap calls
- `lib/apix.dart` — export
- `test/auth/auth_interceptor_test.dart` — add cases
- `test/auth/token_provider_exception_test.dart` — new
