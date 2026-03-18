# Story 9.1: Implement SecureStorageService

Status: done

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

- [x] Task 1: Create SecureStorageService class
  - [x] Constructor with optional FlutterSecureStorage injection
  - [x] Default FlutterSecureStorage with AndroidOptions(encryptedSharedPreferences: true)
  - [x] write(String key, String value) → Future<void>
  - [x] read(String key) → Future<String?>
  - [x] delete(String key) → Future<void>
  - [x] deleteAll() → Future<void>
  - [x] containsKey(String key) → Future<bool>
  - [x] readAll() → Future<Map<String, String>> (bonus)

- [x] Task 2: Add flutter_secure_storage dependency
  - [x] Add to pubspec.yaml (^9.0.0)
  - [ ] Document installation in README (deferred to 8-1)

- [x] Task 3: Write unit tests
  - [x] Test all CRUD operations
  - [x] Test with mock FlutterSecureStorage
  - [x] Test default options

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
