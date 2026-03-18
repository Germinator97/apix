# Story 9.4: Update AuthInterceptor for Simplified Refresh

Status: backlog

## Story

As a developer,
I want AuthInterceptor to handle refresh calls automatically,
so that I only need to provide the endpoint URL.

## Acceptance Criteria

1. **Given** AuthConfig with refreshEndpoint
   **When** a 401 is received
   **Then** AuthInterceptor calls refreshEndpoint with refresh token

2. **Given** successful refresh response
   **When** onTokenRefreshed callback is provided
   **Then** callback is invoked with raw Response

3. **Given** refreshHeaders in AuthConfig
   **When** refresh request is made
   **Then** custom headers are included

4. **Given** AuthConfig with old onRefresh callback
   **When** refresh is triggered
   **Then** old behavior is preserved (backward compatible)

## Tasks / Subtasks

- [ ] Task 1: Update AuthInterceptor._handleRefresh()
  - [ ] Check if refreshEndpoint is configured
  - [ ] If yes, make POST request to refreshEndpoint
  - [ ] Include refresh token in body with configured key
  - [ ] Include refreshHeaders if provided
  - [ ] Call onTokenRefreshed with raw Response
  - [ ] Return true if callback completes without error

- [ ] Task 2: Maintain backward compatibility
  - [ ] If refreshEndpoint is null, use existing onRefresh behavior
  - [ ] Priority: refreshEndpoint > onRefresh

- [ ] Task 3: Handle edge cases
  - [ ] Refresh token is null → return false
  - [ ] Network error during refresh → return false
  - [ ] onTokenRefreshed throws → return false

- [ ] Task 4: Write integration tests
  - [ ] Test simplified refresh flow
  - [ ] Test with custom headers
  - [ ] Test backward compatibility
  - [ ] Test error scenarios

## Dev Notes

### Implementation Pattern

```dart
Future<bool> _handleRefresh() async {
  // ... existing queue logic ...

  try {
    // New simplified flow
    if (config.refreshEndpoint != null) {
      final refreshToken = await config.tokenProvider.getRefreshToken();
      if (refreshToken == null) {
        _refreshSuccess = false;
        return false;
      }

      final response = await _dio.post(
        config.refreshEndpoint!,
        data: {config.refreshTokenBodyKey: refreshToken},
        options: Options(headers: config.refreshHeaders),
      );

      if (config.onTokenRefreshed != null) {
        await config.onTokenRefreshed!(response);
      }
      
      _refreshSuccess = true;
      return true;
    }

    // Fallback to existing onRefresh behavior
    if (config.onRefresh != null) {
      _refreshSuccess = await config.onRefresh!(config.tokenProvider);
      return _refreshSuccess;
    }

    return false;
  } catch (e) {
    _refreshSuccess = false;
    return false;
  }
}
```

### References

- [PRD: FR50-FR52]
- [Product Brief: SecureTokenProvider]

## Dev Agent Record

### File List (Target)

- `lib/src/auth/auth_interceptor.dart` - Updated AuthInterceptor
- `test/auth/auth_interceptor_test.dart` - Updated tests
