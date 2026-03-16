# Story 3.3: Handle JSON Requests & Responses

Status: done

## Story

As a developer,
I want to send JSON body and receive JSON responses,
so that I can work with standard API formats.

## Acceptance Criteria

1. **Given** a POST request with Map<String, dynamic> body
   **When** I send the request
   **Then** Content-Type is set to application/json

2. **Given** a JSON response
   **Then** response JSON is accessible as Map

3. **Given** a JSON response
   **Then** I can optionally deserialize to a model via fromJson

## Tasks / Subtasks

- [x] Task 1: Add postJson/putJson/patchJson convenience methods
  - [x] Auto-set Content-Type header
  - [x] Accept Map<String, dynamic> body

- [x] Task 2: Add response deserialization helper
  - [x] Create typed response method with fromJson
  - [x] Added getListAndDecode for list responses

- [x] Task 3: Write unit tests
  - [x] Test JSON content type
  - [x] Test response deserialization

## Dev Notes

### Implementation Pattern

```dart
// Convenience methods
Future<Response<T>> postJson<T>(String path, Map<String, dynamic> body);

// Typed response with fromJson
Future<T> postAndDecode<T>(
  String path,
  Map<String, dynamic> body,
  T Function(Map<String, dynamic>) fromJson,
);
```

### References

- [Source: epics.md#Story 3.3]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Added postJson, putJson, patchJson with auto Content-Type
- Added getAndDecode, postAndDecode, putAndDecode, patchAndDecode
- Added getListAndDecode for list responses
- 7 unit tests passing

### File List

- `lib/src/client/api_client.dart` - Added JSON methods
- `test/client/api_client_json_test.dart` - Unit tests

### Change Log

- 2026-03-16: Story 3.3 implemented - JSON requests/responses
