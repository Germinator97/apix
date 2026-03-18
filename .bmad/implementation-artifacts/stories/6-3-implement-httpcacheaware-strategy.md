# Story 6.3: Implement HttpCacheAware Strategy

Status: done

## Story

As a developer,
I want to respect HTTP cache headers,
so that I follow standard caching semantics.

## Acceptance Criteria

1. **Given** HttpCacheAware strategy
   **When** response has Cache-Control header
   **Then** respect max-age, no-cache, no-store directives

2. **Given** cached response with ETag
   **When** revalidating
   **Then** send If-None-Match header

3. **Given** server returns 304 Not Modified
   **Then** return cached response

4. **Given** no HTTP cache headers
   **Then** fallback to default TTL

## Tasks / Subtasks

- [x] Task 1: Parse Cache-Control header
  - [x] Extract max-age directive
  - [x] Detect no-cache directive
  - [x] Detect no-store directive
  - [x] Detect must-revalidate directive

- [x] Task 2: Handle ETag/If-None-Match
  - [x] Store ETag from response headers
  - [x] Add If-None-Match on revalidation

- [x] Task 3: Handle 304 Not Modified
  - [x] Return cached response on 304
  - [x] Preserve original data

- [x] Task 4: Implement cache directives
  - [x] Use max-age for TTL calculation
  - [x] Skip caching on no-store
  - [x] Fallback to cache on network error

- [x] Task 5: Write unit tests
  - [x] Cache-Control parsing tests
  - [x] ETag/If-None-Match tests
  - [x] 304 handling tests
  - [x] no-store directive test

## Dev Notes

### Implementation Pattern

```dart
final config = CacheConfig(
  strategy: CacheStrategy.httpCacheAware,
);

// Server response with:
// Cache-Control: max-age=3600
// ETag: "abc123"

// Next request automatically adds:
// If-None-Match: "abc123"

// If server returns 304, cached response is used
```

### CacheControlHeader

```dart
class CacheControlHeader {
  final int? maxAge;
  final bool noCache;
  final bool noStore;
  final bool mustRevalidate;
}
```

### References

- [Source: epics.md#Story 6.3]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- CacheControlHeader class for parsed directives
- max-age used for TTL calculation
- ETag stored and sent as If-None-Match
- 304 Not Modified returns cached response
- no-store prevents caching
- Fallback to cache on network error
- 9 new tests (41 total cache tests)

### File List

- `lib/src/cache/cache_interceptor.dart` - HttpCacheAware implementation
- `test/cache/cache_interceptor_test.dart` - Unit tests

### Change Log

- 2026-03-17: Story 6.3 implemented - HttpCacheAware strategy
