# Story 4.3: Implement Configurable Refresh Detection

Status: done

## Story

As a developer,
I want automatic token refresh on configurable status codes,
so that users stay logged in seamlessly.

## Acceptance Criteria

1. **Given** refreshStatusCodes is configured (default: [401])
   **When** a response matches one of these codes
   **Then** refresh is triggered via onRefresh callback

2. **Given** refresh succeeds
   **Then** original request is retried with new token

3. **Given** I need custom refresh codes
   **Then** I can configure [401, 403] or other codes via AuthConfig

## Tasks / Subtasks

- [x] Task 1: Add onRefresh callback to AuthConfig
  - [x] RefreshCallback typedef
  - [x] onRefresh optional parameter
  - [x] shouldRefresh(statusCode) helper method

- [x] Task 2: Extend AuthInterceptor with onError
  - [x] Detect refresh-triggering status codes
  - [x] Call onRefresh callback
  - [x] Retry original request with new token

- [x] Task 3: Write unit tests
  - [x] Test shouldRefresh with configured codes
  - [x] Test onRefresh callback invocation
  - [x] Test no refresh for non-configured codes

## Dev Notes

### Implementation Pattern

```dart
final authConfig = AuthConfig(
  tokenProvider: myProvider,
  refreshStatusCodes: [401, 403],  // configurable
  onRefresh: (provider) async {
    final refreshToken = await provider.getRefreshToken();
    if (refreshToken == null) return false;

    final response = await dio.post('/auth/refresh', data: {
      'refresh_token': refreshToken,
    });

    await provider.saveTokens(
      response.data['access_token'],
      response.data['refresh_token'],
    );
    return true;
  },
);

final interceptor = AuthInterceptor(authConfig, dio);
```

### References

- [Source: epics.md#Story 4.3]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Added RefreshCallback typedef and onRefresh to AuthConfig
- Added shouldRefresh(statusCode) helper method
- Extended AuthInterceptor.onError for refresh detection
- Retries original request after successful refresh
- 25 unit tests passing (auth module)

### File List

- `lib/src/auth/auth_config.dart` - Added onRefresh callback
- `lib/src/auth/auth_interceptor.dart` - Added onError with refresh logic
- `test/auth/auth_interceptor_test.dart` - Added refresh detection tests

### Change Log

- 2026-03-16: Story 4.3 implemented - Configurable refresh detection
