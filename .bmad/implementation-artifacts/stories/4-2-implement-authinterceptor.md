# Story 4.2: Implement AuthInterceptor

Status: done

## Story

As a developer,
I want auth tokens attached automatically to requests,
so that I don't manage headers manually.

## Acceptance Criteria

1. **Given** a TokenProvider is configured via AuthConfig
   **When** I make a request
   **Then** Authorization header is added with Bearer token

2. **Given** custom header configuration
   **Then** I can customize header name via AuthConfig

## Tasks / Subtasks

- [x] Task 1: Create AuthInterceptor class
  - [x] Extends Dio Interceptor
  - [x] Gets token from TokenProvider
  - [x] Adds header using AuthConfig format

- [x] Task 2: Handle edge cases
  - [x] No header when token is null
  - [x] Preserve existing headers
  - [x] Always call handler.next()

- [x] Task 3: Write unit tests
  - [x] Test header addition with token
  - [x] Test no header when null token
  - [x] Test custom header name/prefix

## Dev Notes

### Implementation Pattern

```dart
// Create interceptor with auth config
final authConfig = AuthConfig(
  tokenProvider: myTokenProvider,
  headerName: 'Authorization',  // default
  headerPrefix: 'Bearer',       // default
);

final interceptor = AuthInterceptor(authConfig);

// Add to ApiClientFactory
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  interceptors: [interceptor],
);

// All requests now have Authorization header automatically
await client.get('/users');  // → Authorization: Bearer <token>
```

### References

- [Source: epics.md#Story 4.2]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- AuthInterceptor adds token header automatically
- Respects AuthConfig for header name/prefix
- Skips header when token is null
- 7 unit tests passing

### File List

- `lib/src/auth/auth_interceptor.dart` - AuthInterceptor class
- `test/auth/auth_interceptor_test.dart` - Unit tests

### Change Log

- 2026-03-16: Story 4.2 implemented - AuthInterceptor
