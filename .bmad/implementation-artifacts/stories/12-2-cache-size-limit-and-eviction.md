# Story 12.2: Add cache size-based limit and onEviction callback

Status: ready-for-dev

## Story

As a developer,
I want `InMemoryCacheStorage` to support byte-based size limits and an `onEviction` callback,
so that I can bound memory usage on mobile and instrument cache pressure.

## Context (why)

`InMemoryCacheStorage.maxEntries` (added in 2.0.0) is count-based. On mobile, response payload size varies wildly — caching 100 entries of 1 KB is fine, 100 entries of 200 KB is a 20 MB hit on RAM. A device with 1 GB free RAM tolerates very different cache budgets than a device with 100 MB free.

Without an eviction callback, developers can't observe cache pressure to tune their config or trigger metrics.

## Acceptance Criteria

1. **Given** `InMemoryCacheStorage(maxBytes: 1024 * 1024)` (1 MB)
   **When** total cached payload size would exceed 1 MB on the next `set()`
   **Then** oldest entries are evicted (FIFO) until the new entry fits

2. **Given** both `maxEntries: 100` and `maxBytes: 1024 * 1024` configured
   **When** either limit is hit on `set()`
   **Then** FIFO eviction continues until both limits are satisfied

3. **Given** `CacheConfig.onEviction: (key, reason) => ...`
   **When** an entry is evicted (either limit) or `remove()`/`clear()` is called
   **Then** the callback is invoked synchronously with the key and reason
   **And** reasons: `EvictionReason.maxEntriesExceeded`, `maxBytesExceeded`, `manual`, `expired`

4. **Given** an entry larger than `maxBytes` alone
   **When** `set()` is called
   **Then** the entry is **rejected** (not stored), `onEviction(key, oversized)` is called
   **And** the call returns without throwing

5. **Given** `maxBytes` is null (default)
   **Then** behavior is unchanged (count-based eviction only — regression)

6. **Given** `onEviction` callback throws
   **Then** the throw is caught and ignored (must not corrupt cache state)

## Tasks / Subtasks

- [ ] Task 1: Define eviction types
  - [ ] `enum EvictionReason { maxEntriesExceeded, maxBytesExceeded, oversized, manual, expired }`
  - [ ] `typedef CacheEvictionCallback = void Function(String key, EvictionReason reason);`

- [ ] Task 2: Update `InMemoryCacheStorage`
  - [ ] Add `maxBytes` field
  - [ ] Add `onEviction` callback
  - [ ] Track total bytes (sum of `entry.body.length` or `jsonEncode(entry).length`)
  - [ ] Helper to compute entry size — use `utf8.encode(jsonEncode(entry.toJson())).length`
  - [ ] Update `_evictIfNeeded` to consider both limits
  - [ ] Reject oversized entries (AC4)
  - [ ] Wrap callback in try/catch (AC6)

- [ ] Task 3: Update `CacheConfig`
  - [ ] Pass `maxBytes` and `onEviction` through to default storage
  - [ ] Document trade-offs in dartdoc

- [ ] Task 4: Unit tests
  - [ ] Set entries totaling exactly `maxBytes` → no eviction
  - [ ] Exceed `maxBytes` → FIFO eviction with `maxBytesExceeded` reason
  - [ ] Exceed `maxEntries` and `maxBytes` simultaneously → both fire correctly
  - [ ] Oversized entry → rejected, callback fires with `oversized`
  - [ ] `remove()` and `clear()` invoke callback with `manual`
  - [ ] Callback throws → cache state intact, no exception escapes
  - [ ] `maxBytes: null` → no byte tracking overhead (regression)

## Dev Notes

### Implementation pattern

```dart
class InMemoryCacheStorage implements CacheStorage {
  final int? maxEntries;
  final int? maxBytes;
  final CacheEvictionCallback? onEviction;

  final _entries = <String, CacheEntry>{};
  final _sizes = <String, int>{};
  int _totalBytes = 0;

  void _evictIfNeeded(int incomingSize) {
    while (_entries.isNotEmpty &&
        ((maxEntries != null && _entries.length >= maxEntries!) ||
         (maxBytes != null && _totalBytes + incomingSize > maxBytes!))) {
      final oldestKey = _entries.keys.first;
      _evict(oldestKey,
        maxBytes != null && _totalBytes + incomingSize > maxBytes!
          ? EvictionReason.maxBytesExceeded
          : EvictionReason.maxEntriesExceeded);
    }
  }

  void _evict(String key, EvictionReason reason) {
    final size = _sizes.remove(key) ?? 0;
    _entries.remove(key);
    _totalBytes -= size;
    _safeNotify(key, reason);
  }

  void _safeNotify(String key, EvictionReason reason) {
    if (onEviction == null) return;
    try { onEviction!(key, reason); } catch (_) { /* swallow per AC6 */ }
  }
}
```

### Trade-off note

Computing the size via `jsonEncode` adds CPU overhead per `set()`. Acceptable: cache writes are infrequent compared to reads. If profiling shows it's a hot path, switch to a coarse estimate (e.g. `body is String ? body.length : body.toString().length`).

### References

- `lib/src/cache/cache_storage.dart:64` — current `maxEntries` implementation
- `lib/src/cache/cache_config.dart`
- `lib/src/cache/cache_entry.dart`

## Dev Agent Record

### File List (Target)

- `lib/src/cache/cache_storage.dart` — extend `InMemoryCacheStorage`
- `lib/src/cache/cache_config.dart` — wire through new params
- `lib/apix.dart` — export `EvictionReason`, callback typedef
- `test/cache/cache_storage_test.dart` — extend
