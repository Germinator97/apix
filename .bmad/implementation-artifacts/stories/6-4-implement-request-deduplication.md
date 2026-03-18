# Story 6.4: Implement Request Deduplication

Status: done

## Story

As a developer,
I want identical concurrent requests deduplicated,
So that I don't waste bandwidth.

## Acceptance Criteria

1. **Given** multiple identical GET requests in flight
   **When** they hit the cache interceptor
   **Then** only one network request is made

2. **Given** deduplication is active
   **Then** all callers receive the same response

3. **Given** request deduplication key
   **Then** based on URL + method + body hash

4. **Given** original request fails
   **Then** all waiters receive the error

## Tasks / Subtasks

- [x] Task 1: Create RequestDeduplicator class
  - [x] Implement Completer-based deduplication
  - [x] Generate unique key from method + URL + body hash
  - [x] Track pending requests

- [x] Task 2: Integrate with CacheConfig
  - [x] Add enableDeduplication flag
  - [x] Add deduplicateMethods list
  - [x] Add shouldDeduplicate method

- [x] Task 3: Integrate with CacheInterceptor
  - [x] Use deduplicator for networkFirst/networkOnly
  - [x] Execute deduplicated requests
  - [x] Handle fallback to cache on error

- [x] Task 4: Write unit tests
  - [x] Key generation tests
  - [x] Concurrent request deduplication
  - [x] Error propagation to all waiters
  - [x] Config integration tests

## Dev Notes

### Usage Example

```dart
final config = CacheConfig(
  enableDeduplication: true,  // default
  deduplicateMethods: ['GET'],  // default
);

final interceptor = CacheInterceptor(config: config);

// These concurrent calls result in only one network request
final results = await Future.wait([
  client.get('/users'),
  client.get('/users'),
  client.get('/users'),
]);
// All receive the same response
```

### RequestDeduplicator

```dart
class RequestDeduplicator {
  Future<Response> deduplicate(
    RequestOptions options,
    Future<Response> Function() execute,
  );
  
  String generateKey(RequestOptions options);
  int get pendingCount;
  bool hasPending(RequestOptions options);
}
```

### References

- [Source: epics.md#Story 6.4]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- RequestDeduplicator with Completer pattern
- MD5 hash for body deduplication
- Integrated with CacheConfig (enableDeduplication, deduplicateMethods)
- 12 new tests (53 total cache tests)
- crypto package added for MD5

### File List

- `lib/src/cache/request_deduplicator.dart` - New deduplicator class
- `lib/src/cache/cache_config.dart` - Deduplication config
- `lib/src/cache/cache_interceptor.dart` - Integration
- `lib/apix.dart` - Export
- `test/cache/request_deduplicator_test.dart` - Unit tests
- `pubspec.yaml` - crypto dependency

### Change Log

- 2026-03-17: Story 6.4 implemented - Request deduplication
