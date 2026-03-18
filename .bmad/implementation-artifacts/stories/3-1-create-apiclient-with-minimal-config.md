# Story 3.1: Create ApiClient with Minimal Config

Status: done

## Story

As a developer,
I want to create an ApiClient with just a baseUrl,
so that I can start making requests immediately.

## Acceptance Criteria

1. **Given** I instantiate ApiClient(baseUrl: 'https://api.example.com')
   **Then** the client is ready to use with sensible defaults

2. **Given** I create an ApiClient
   **Then** timeout defaults to 30 seconds

3. **Given** I create an ApiClient
   **Then** I can optionally provide custom timeout, headers, interceptors

## Tasks / Subtasks

- [x] Task 1: Create ApiClientConfig class
  - [x] Create `lib/src/client/api_client_config.dart`
  - [x] Define baseUrl, timeout, headers, interceptors

- [x] Task 2: Create ApiClient class (AC: #1, #2, #3)
  - [x] Create `lib/src/client/api_client.dart`
  - [x] Wrap Dio instance
  - [x] Accept config with sensible defaults
  - [x] Default timeout = 30 seconds

- [x] Task 3: Export from barrel file
  - [x] Update `lib/apix.dart`

- [x] Task 4: Write unit tests
  - [x] Test default configuration
  - [x] Test custom configuration
  - [x] Test timeout default

## Dev Notes

### Architecture Requirements

**From ADR-002:**
```dart
final client = ApiClient(
  baseUrl: 'https://api.example.com',
  authConfig: AuthConfig(tokenProvider: myTokenProvider),  // optional
  retryConfig: RetryConfig(maxAttempts: 3),                // optional
  cacheConfig: CacheConfig(strategy: CacheStrategy.networkFirst), // optional
);
```

### Dependencies

- dio: ^5.0.0 (already in pubspec.yaml)

### References

- [Source: architecture.md#ADR-002]
- [Source: epics.md#Story 3.1]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Created ApiClientConfig with baseUrl, timeouts, headers, interceptors
- Created ApiClient wrapping Dio with sensible defaults
- Default timeout = 30 seconds (connect, receive, send)
- 13 unit tests passing

### File List

- `lib/src/client/api_client_config.dart` - Configuration class
- `lib/src/client/api_client.dart` - Main client class
- `lib/apix.dart` - Updated barrel export
- `test/client/api_client_test.dart` - Unit tests

### Change Log

- 2026-03-16: Story 3.1 implemented - ApiClient with minimal config
