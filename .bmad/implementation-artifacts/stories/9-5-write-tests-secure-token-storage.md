# Story 9.5: Write Tests for Secure Token Storage

Status: backlog

## Story

As a maintainer,
I want comprehensive tests for SecureTokenProvider feature,
so that the implementation is reliable and regression-free.

## Acceptance Criteria

1. **Given** SecureStorageService
   **When** all methods are tested
   **Then** coverage > 90%

2. **Given** SecureTokenProvider
   **When** all scenarios are tested
   **Then** TokenProvider contract is verified

3. **Given** AuthInterceptor with refreshEndpoint
   **When** integration tested
   **Then** simplified refresh flow works end-to-end

## Tasks / Subtasks

- [ ] Task 1: Unit tests for SecureStorageService
  - [ ] Test write/read/delete/deleteAll
  - [ ] Test containsKey
  - [ ] Test with custom FlutterSecureStorage
  - [ ] Test default options

- [ ] Task 2: Unit tests for SecureTokenProvider
  - [ ] Test TokenProvider interface compliance
  - [ ] Test saveTokens/clearTokens
  - [ ] Test getAccessToken/getRefreshToken
  - [ ] Test custom keys
  - [ ] Test storage injection
  - [ ] Test storage getter exposure

- [ ] Task 3: Integration tests for AuthInterceptor
  - [ ] Test refreshEndpoint auto-call
  - [ ] Test onTokenRefreshed callback
  - [ ] Test refreshHeaders inclusion
  - [ ] Test backward compatibility with onRefresh
  - [ ] Test error handling (network, null token, callback error)

- [ ] Task 4: E2E test scenario
  - [ ] Login → save tokens → request → 401 → auto refresh → retry → success

## Dev Notes

### Test Setup

```dart
// Mock for FlutterSecureStorage
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// Mock for SecureStorageService
class MockSecureStorageService extends Mock implements SecureStorageService {}

// Test helper
SecureTokenProvider createTestProvider() {
  final mockStorage = MockSecureStorageService();
  return SecureTokenProvider(storage: mockStorage);
}
```

### References

- [PRD: NFR4 - Test coverage > 90%]

## Dev Agent Record

### File List (Target)

- `test/auth/secure_storage_service_test.dart`
- `test/auth/secure_token_provider_test.dart`
- `test/auth/auth_interceptor_refresh_test.dart`
