# Story 6.2: Implement CacheFirst & NetworkFirst

Status: done

## Story

As a developer,
I want basic cache strategies,
so that I control freshness vs speed tradeoffs.

## Acceptance Criteria

1. **Given** CacheConfig with strategy CacheFirst
   **When** cache exists
   **Then** return cached response immediately

2. **Given** CacheConfig with strategy NetworkFirst
   **When** network succeeds
   **Then** return network response and update cache

3. **Given** NetworkFirst strategy
   **When** network fails
   **Then** fallback to cache if available

## Tasks / Subtasks

- [x] Task 1: Create CacheInterceptor
  - [x] Extends Dio Interceptor
  - [x] onRequest handles CacheFirst/CacheOnly
  - [x] onResponse caches successful responses
  - [x] onError handles NetworkFirst fallback

- [x] Task 2: Implement strategies
  - [x] CacheFirst: return cache if available
  - [x] NetworkFirst: try network, fallback to cache
  - [x] CacheOnly: cache or fail
  - [x] NetworkOnly: never cache

- [x] Task 3: Cache key generation
  - [x] Based on method + URL + query params
  - [x] Sorted query params for consistency

- [x] Task 4: Per-request cache control
  - [x] setCacheStrategy() extension
  - [x] noCache() to force network
  - [x] isFromCache() helper

- [x] Task 5: Write unit tests
  - [x] CacheFirst tests
  - [x] NetworkFirst tests
  - [x] CacheOnly tests
  - [x] Per-request override tests

## Dev Notes

### Implementation Pattern

```dart
final cacheInterceptor = CacheInterceptor(
  config: CacheConfig(
    strategy: CacheStrategy.networkFirst,
    defaultTtl: Duration(minutes: 5),
  ),
);

dio.interceptors.add(cacheInterceptor);

// Per-request override
final options = RequestOptions(path: '/users');
options.setCacheStrategy(CacheStrategy.cacheFirst);
options.noCache(); // Force network

// Check if response is from cache
if (CacheRequestExtension.isFromCache(response)) {
  // Handle cached response
}
```

### References

- [Source: epics.md#Story 6.2]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- CacheInterceptor with all strategies
- Per-request cache control
- Cache key includes query params
- CacheException for cache failures
- 14 new tests (32 total cache tests)

### File List

- `lib/src/cache/cache_interceptor.dart` - CacheInterceptor
- `test/cache/cache_interceptor_test.dart` - Unit tests

### Change Log

- 2026-03-17: Story 6.2 implemented - CacheFirst & NetworkFirst
