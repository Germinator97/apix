# Story 4.1: Create TokenProvider Interface

Status: done

## Story

As a developer,
I want to implement a TokenProvider interface,
so that apix can manage my tokens.

## Acceptance Criteria

1. **Given** I need to provide token management
   **When** I implement TokenProvider
   **Then** I provide getAccessToken(), getRefreshToken(), saveTokens(), clearTokens()

2. **Given** all TokenProvider methods
   **Then** they are async for secure storage compatibility

## Tasks / Subtasks

- [x] Task 1: Create TokenProvider interface (ADR-007)
  - [x] getAccessToken() → Future<String?>
  - [x] getRefreshToken() → Future<String?>
  - [x] saveTokens(String access, String refresh) → Future<void>
  - [x] clearTokens() → Future<void>

- [x] Task 2: Create AuthConfig class
  - [x] tokenProvider (required)
  - [x] headerName (default: 'Authorization')
  - [x] headerPrefix (default: 'Bearer')
  - [x] refreshStatusCodes (default: [401])
  - [x] formatHeaderValue() helper
  - [x] copyWith() method

- [x] Task 3: Write unit tests
  - [x] Test MockTokenProvider implementation
  - [x] Test AuthConfig defaults and customization

## Dev Notes

### Implementation Pattern

```dart
// Implement TokenProvider for your storage
class MyTokenProvider implements TokenProvider {
  final FlutterSecureStorage _storage;

  @override
  Future<String?> getAccessToken() => _storage.read(key: 'access_token');

  @override
  Future<String?> getRefreshToken() => _storage.read(key: 'refresh_token');

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  @override
  Future<void> clearTokens() async {
    await _storage.deleteAll();
  }
}

// Configure auth
final authConfig = AuthConfig(
  tokenProvider: MyTokenProvider(),
  refreshStatusCodes: [401, 403],
);
```

### References

- [Source: epics.md#Story 4.1]
- [ADR-007: TokenProvider - Async Interface]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- ADR-007: TokenProvider interface with async methods
- AuthConfig for configurable auth behavior
- 13 unit tests passing

### File List

- `lib/src/auth/token_provider.dart` - TokenProvider interface
- `lib/src/auth/auth_config.dart` - AuthConfig class
- `test/auth/token_provider_test.dart` - Unit tests

### Change Log

- 2026-03-16: Story 4.1 implemented - TokenProvider interface and AuthConfig
