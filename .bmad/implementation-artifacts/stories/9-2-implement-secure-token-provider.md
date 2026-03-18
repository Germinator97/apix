# Story 9.2: Implement SecureTokenProvider

Status: done

## Story

As a developer,
I want a ready-to-use SecureTokenProvider implementation,
so that I don't have to implement TokenProvider manually.

## Acceptance Criteria

1. **Given** I need token management
   **When** I create a SecureTokenProvider
   **Then** it implements TokenProvider interface

2. **Given** SecureTokenProvider
   **When** I call saveTokens(access, refresh)
   **Then** tokens are stored securely via SecureStorageService

3. **Given** SecureTokenProvider
   **When** I want to share storage with other services
   **Then** I can inject my own SecureStorageService

4. **Given** SecureTokenProvider
   **When** I want custom storage keys
   **Then** I can configure accessTokenKey and refreshTokenKey

## Tasks / Subtasks

- [x] Task 1: Create SecureTokenProvider class
  - [x] Implement TokenProvider interface
  - [x] Constructor with optional SecureStorageService injection
  - [x] Configurable storage keys (default: 'apix_access_token', 'apix_refresh_token')
  - [x] getAccessToken() using SecureStorageService.read()
  - [x] getRefreshToken() using SecureStorageService.read()
  - [x] saveTokens() using SecureStorageService.write()
  - [x] clearTokens() using SecureStorageService.delete()

- [x] Task 2: Expose storage for secondary usage
  - [x] Getter for SecureStorageService instance
  - [x] Document usage for other secrets (Firebase Auth, API keys)

- [x] Task 3: Write unit tests
  - [x] Test TokenProvider interface compliance
  - [x] Test with mock SecureStorageService
  - [x] Test custom keys configuration
  - [x] Test storage sharing scenario

## Dev Notes

### Implementation Pattern

```dart
class SecureTokenProvider implements TokenProvider {
  final SecureStorageService _storage;
  final String accessTokenKey;
  final String refreshTokenKey;

  SecureTokenProvider({
    SecureStorageService? storage,
    this.accessTokenKey = 'apix_access_token',
    this.refreshTokenKey = 'apix_refresh_token',
  }) : _storage = storage ?? SecureStorageService();

  /// Access to underlying storage for secondary usage
  SecureStorageService get storage => _storage;

  @override
  Future<String?> getAccessToken() => _storage.read(accessTokenKey);

  @override
  Future<String?> getRefreshToken() => _storage.read(refreshTokenKey);

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(accessTokenKey, accessToken);
    await _storage.write(refreshTokenKey, refreshToken);
  }

  @override
  Future<void> clearTokens() async {
    await _storage.delete(accessTokenKey);
    await _storage.delete(refreshTokenKey);
  }
}
```

### References

- [PRD: FR45-FR47, FR53]
- [Product Brief: SecureTokenProvider]

## Dev Agent Record

### File List (Target)

- `lib/src/auth/secure_token_provider.dart` - SecureTokenProvider class
- `test/auth/secure_token_provider_test.dart` - Unit tests
