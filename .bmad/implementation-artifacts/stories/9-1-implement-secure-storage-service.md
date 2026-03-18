# Story 9.1: Implement SecureStorageService

Status: backlog

## Story

As a developer,
I want a SecureStorageService wrapper for flutter_secure_storage,
so that I can securely store key-value pairs without boilerplate.

## Acceptance Criteria

1. **Given** I need secure storage
   **When** I create a SecureStorageService
   **Then** I can use write(), read(), delete(), deleteAll() methods

2. **Given** SecureStorageService
   **When** I don't provide a custom FlutterSecureStorage
   **Then** a default instance with recommended Android options is used

3. **Given** SecureStorageService
   **When** I want custom FlutterSecureStorage options
   **Then** I can inject my own instance

## Tasks / Subtasks

- [ ] Task 1: Create SecureStorageService class
  - [ ] Constructor with optional FlutterSecureStorage injection
  - [ ] Default FlutterSecureStorage with AndroidOptions(encryptedSharedPreferences: true)
  - [ ] write(String key, String value) → Future<void>
  - [ ] read(String key) → Future<String?>
  - [ ] delete(String key) → Future<void>
  - [ ] deleteAll() → Future<void>
  - [ ] containsKey(String key) → Future<bool>

- [ ] Task 2: Add flutter_secure_storage dependency
  - [ ] Add to pubspec.yaml as optional peer dependency
  - [ ] Document installation in README

- [ ] Task 3: Write unit tests
  - [ ] Test all CRUD operations
  - [ ] Test with mock FlutterSecureStorage
  - [ ] Test default options

## Dev Notes

### Implementation Pattern

```dart
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> read(String key) async {
    return _storage.read(key: key);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
```

### References

- [PRD: FR43-FR44]
- [Product Brief: SecureTokenProvider]

## Dev Agent Record

### File List (Target)

- `lib/src/auth/secure_storage_service.dart` - SecureStorageService class
- `test/auth/secure_storage_service_test.dart` - Unit tests
