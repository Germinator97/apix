# Story 9.6: Update Documentation and Examples

Status: done

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

- [x] Task 1: Export new classes in apix.dart
  - [x] Export SecureStorageService
  - [x] Export SecureTokenProvider

- [ ] Task 2: Update README.md (deferred to 8-1)
  - [ ] Add SecureTokenProvider section
  - [ ] Show basic and advanced usage

- [ ] Task 3: Update example app (deferred to 8-3)
  - [ ] Use SecureTokenProvider

- [x] Task 4: Inline documentation
  - [x] SecureStorageService - documented with dartdoc
  - [x] SecureTokenProvider - documented with dartdoc
  - [x] AuthConfig new fields - documented with dartdoc

- [x] Task 5: Update CHANGELOG
  - [x] Add v0.3.0 section
  - [x] List new features (SecureStorageService, SecureTokenProvider, refreshEndpoint)
  - [x] Note backward compatibility

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
