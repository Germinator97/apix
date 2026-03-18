# Story 3.5: Provide Raw Response Access

Status: done

## Story

As a developer,
I want to access the raw Dio Response when needed,
so that I can handle special cases.

## Acceptance Criteria

1. **Given** any request
   **When** I need raw response
   **Then** I can access statusCode, headers, data directly

2. **Given** all HTTP methods
   **Then** they return Response<T> with full access to raw data

## Tasks / Subtasks

- [x] Task 1: Verify Response<T> is returned from all HTTP methods
  - [x] get() returns Response<T>
  - [x] post() returns Response<T>
  - [x] put() returns Response<T>
  - [x] delete() returns Response<T>
  - [x] patch() returns Response<T>

- [x] Task 2: Verify raw Dio access via getter
  - [x] `dio` getter exposes underlying Dio instance

- [x] Task 3: Document usage in examples

## Dev Notes

### Implementation Pattern

```dart
// All HTTP methods return Response<T> - full access to raw response
final response = await client.get<Map<String, dynamic>>('/users/1');

// Access raw response properties
print(response.statusCode);        // 200
print(response.headers);           // Headers
print(response.data);              // Map<String, dynamic>
print(response.requestOptions);    // RequestOptions
print(response.extra);             // Map<String, dynamic>

// For advanced cases, access Dio directly
client.dio.fetch(requestOptions);
```

### References

- [Source: epics.md#Story 3.5]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Already implemented by design - all HTTP methods return Response<T>
- Response<T> provides: statusCode, headers, data, requestOptions, extra
- `dio` getter available for advanced direct Dio access
- No additional code needed - story satisfied by existing implementation

### File List

- `lib/src/client/api_client.dart` - HTTP methods return Response<T>

### Change Log

- 2026-03-16: Story 3.5 verified - raw response access already available
