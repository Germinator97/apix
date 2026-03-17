# Story 6.1: Create CacheStorage Interface

Status: done

## Story

As a developer,
I want a CacheStorage abstraction,
so that I can use any storage backend.

## Acceptance Criteria

1. **Given** CacheStorage interface
   **Then** it provides get(), set(), remove(), clear() methods

2. **Given** default implementation
   **Then** InMemoryCacheStorage is provided

3. **Given** I need custom storage
   **Then** I can provide custom implementation via CacheConfig

## Tasks / Subtasks

- [x] Task 1: Create CacheEntry model
  - [x] data, statusCode, createdAt, expiresAt
  - [x] etag and headers optional
  - [x] isExpired, isValid, remainingTtl getters
  - [x] withTtl factory
  - [x] toJson/fromJson serialization

- [x] Task 2: Create CacheStorage interface
  - [x] get(key) → Future<CacheEntry?>
  - [x] set(key, entry) → Future<void>
  - [x] remove(key) → Future<void>
  - [x] clear() → Future<void>
  - [x] has(key) → Future<bool>
  - [x] keys() → Future<List<String>>

- [x] Task 3: Implement InMemoryCacheStorage
  - [x] Map-based storage
  - [x] Auto-remove expired entries on get
  - [x] length getter

- [x] Task 4: Create CacheConfig class
  - [x] storage (default: InMemoryCacheStorage)
  - [x] strategy enum (cacheFirst, networkFirst, etc.)
  - [x] defaultTtl (default: 5 minutes)
  - [x] cacheableMethods (default: ['GET'])
  - [x] shouldCache(method) helper

- [x] Task 5: Write unit tests
  - [x] CacheEntry tests
  - [x] InMemoryCacheStorage tests
  - [x] CacheConfig tests

## Dev Notes

### Implementation Pattern

```dart
// Use default in-memory storage
final config = CacheConfig();

// Custom storage backend
class MyStorage implements CacheStorage {
  @override
  Future<CacheEntry?> get(String key) async { ... }
  // ...
}

final config = CacheConfig(
  storage: MyStorage(),
  strategy: CacheStrategy.networkFirst,
  defaultTtl: Duration(minutes: 10),
);
```

### References

- [Source: epics.md#Story 6.1]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- CacheEntry with TTL and serialization
- CacheStorage abstract interface
- InMemoryCacheStorage default implementation
- CacheConfig with strategy enum
- 18 unit tests passing

### File List

- `lib/src/cache/cache_entry.dart` - CacheEntry model
- `lib/src/cache/cache_storage.dart` - CacheStorage + InMemoryCacheStorage
- `lib/src/cache/cache_config.dart` - CacheConfig + CacheStrategy
- `test/cache/cache_storage_test.dart` - Unit tests

### Change Log

- 2026-03-17: Story 6.1 implemented - CacheStorage interface
