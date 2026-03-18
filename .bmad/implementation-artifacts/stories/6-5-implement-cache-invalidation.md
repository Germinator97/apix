# Story 6.5: Implement Cache Invalidation

Status: done

## Story

As a developer,
I want to invalidate cache programmatically,
So that I can force fresh data.

## Acceptance Criteria

1. **Given** cached data exists
   **When** I call `invalidate(key)`
   **Then** the specified cache entry is removed

2. **Given** cached data exists
   **When** I call `clearCache()`
   **Then** all cache entries are removed

3. **Given** cache invalidated
   **When** next request is made
   **Then** fresh data is fetched from network

## Tasks / Subtasks

- [x] Task 1: Add invalidation methods to CacheStorage
  - [x] Add removeWhere(predicate) method
  - [x] Add removeByPrefix(prefix) method
  - [x] Implement in InMemoryCacheStorage

- [x] Task 2: Add invalidation API to CacheInterceptor
  - [x] invalidate(key) - remove specific entry
  - [x] invalidateUrl(url, method) - remove by URL
  - [x] invalidateWhere(predicate) - remove by condition
  - [x] invalidateByPrefix(prefix) - remove by key prefix
  - [x] invalidatePath(pattern) - remove by path pattern
  - [x] clearCache() - remove all entries
  - [x] getCacheKeys() - list all keys
  - [x] hasCache(key) - check existence

- [x] Task 3: Write unit tests
  - [x] CacheStorage invalidation tests
  - [x] CacheInterceptor invalidation tests

## Dev Notes

### Usage Examples

```dart
final interceptor = CacheInterceptor(config: config);

// Invalidate specific entry
await interceptor.invalidate('GET:https://api.com/users/1');

// Invalidate by URL
await interceptor.invalidateUrl('https://api.com/users/1');

// Invalidate all user-related cache
await interceptor.invalidateWhere((key) => key.contains('/users'));

// Invalidate by prefix
await interceptor.invalidateByPrefix('GET:https://api.com/users');

// Invalidate by path pattern
await interceptor.invalidatePath('/users');

// Clear all cache
await interceptor.clearCache();

// Check cache state
final keys = await interceptor.getCacheKeys();
final exists = await interceptor.hasCache('GET:https://api.com/users');
```

### References

- [Source: epics.md#Story 6.5]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- CacheStorage: removeWhere, removeByPrefix
- CacheInterceptor: 8 invalidation methods
- 11 new tests (64 total cache tests)
- Epic 6 complete

### File List

- `lib/src/cache/cache_storage.dart` - Invalidation methods
- `lib/src/cache/cache_interceptor.dart` - Invalidation API
- `test/cache/cache_storage_test.dart` - Storage tests
- `test/cache/cache_interceptor_test.dart` - Interceptor tests

### Change Log

- 2026-03-17: Story 6.5 implemented - Cache invalidation
- 2026-03-17: Epic 6 complete
