# Story 9.6: Update Documentation and Examples

Status: backlog

## Story

As a developer,
I want clear documentation for SecureTokenProvider,
so that I can integrate it quickly.

## Acceptance Criteria

1. **Given** README.md
   **When** I look for token storage
   **Then** I find SecureTokenProvider section

2. **Given** example app
   **When** I look for auth example
   **Then** I find SecureTokenProvider usage

3. **Given** API documentation
   **When** I read SecureStorageService/SecureTokenProvider
   **Then** all public APIs are documented

## Tasks / Subtasks

- [ ] Task 1: Update README.md
  - [ ] Add SecureTokenProvider section
  - [ ] Show basic usage (1-3 lines)
  - [ ] Show advanced usage (custom storage, keys)
  - [ ] Show refresh flow with onTokenRefreshed
  - [ ] Add migration guide from manual TokenProvider

- [ ] Task 2: Update example app
  - [ ] Use SecureTokenProvider instead of manual implementation
  - [ ] Show login → save tokens flow
  - [ ] Show logout → clear tokens flow
  - [ ] Show refresh with onTokenRefreshed

- [ ] Task 3: Add inline documentation
  - [ ] Document SecureStorageService class and methods
  - [ ] Document SecureTokenProvider class and methods
  - [ ] Document new AuthConfig fields
  - [ ] Add code examples in dartdoc

- [ ] Task 4: Update CHANGELOG
  - [ ] Add v0.3.0 section
  - [ ] List new features
  - [ ] Note backward compatibility

## Dev Notes

### README Section

```markdown
## Secure Token Storage

ApiX provides `SecureTokenProvider`, a ready-to-use `TokenProvider` 
implementation using `flutter_secure_storage`.

### Basic Usage

```dart
final client = ApiClient(
  baseUrl: 'https://api.example.com',
  authConfig: AuthConfig(
    tokenProvider: SecureTokenProvider(),
    refreshEndpoint: '/auth/refresh',
    onTokenRefreshed: (response) async {
      final data = response.data;
      await tokenProvider.saveTokens(
        data['access_token'],
        data['refresh_token'],
      );
    },
  ),
);
```

### Advanced Usage

```dart
// Share storage with other services
final storage = SecureStorageService();
final tokenProvider = SecureTokenProvider(storage: storage);

// Store other secrets
await storage.write('firebase_token', firebaseToken);
```
```

### References

- [PRD: FR43-FR53]

## Dev Agent Record

### File List (Target)

- `README.md` - Updated documentation
- `example/lib/main.dart` - Updated example
- `CHANGELOG.md` - Version 0.3.0 notes
