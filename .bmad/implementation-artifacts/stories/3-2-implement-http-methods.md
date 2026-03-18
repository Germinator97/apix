# Story 3.2: Implement HTTP Methods

Status: done

## Story

As a developer,
I want to make GET, POST, PUT, DELETE, PATCH requests,
so that I can interact with any REST API.

## Acceptance Criteria

1. **Given** an ApiClient instance
   **When** I call client.get('/path')
   **Then** a GET request is sent

2. **Given** an ApiClient instance
   **Then** POST, PUT, DELETE, PATCH methods work similarly

3. **Given** any HTTP method
   **Then** I can pass headers, queryParams, body as needed

## Tasks / Subtasks

- [x] Task 1: Add HTTP methods to ApiClient (AC: #1, #2, #3)
  - [x] Implement get() method
  - [x] Implement post() method
  - [x] Implement put() method
  - [x] Implement delete() method
  - [x] Implement patch() method

- [x] Task 2: Write unit tests with mocked Dio
  - [x] Test each HTTP method
  - [x] Test with query parameters
  - [x] Test with headers
  - [x] Test with body

## Dev Notes

### Method Signatures

```dart
Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters, Options? options});
Future<Response<T>> post<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options});
Future<Response<T>> put<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options});
Future<Response<T>> delete<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options});
Future<Response<T>> patch<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options});
```

### References

- [Source: epics.md#Story 3.2]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Added GET, POST, PUT, DELETE, PATCH methods to ApiClient
- All methods support queryParameters, options, cancelToken
- POST/PUT/PATCH support data and progress callbacks
- 9 unit tests passing with mocked Dio

### File List

- `lib/src/client/api_client.dart` - Added HTTP methods
- `test/client/api_client_http_methods_test.dart` - Unit tests

### Change Log

- 2026-03-16: Story 3.2 implemented - HTTP methods
