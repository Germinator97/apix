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

- [x] Task 1: Default Content-Type to application/json (ADR-010)
  - [x] Add defaultContentType to ApiClientConfig (default: 'application/json')
  - [x] Create MultipartInterceptor for auto-detection (ADR-009)
  - [x] Auto-detect File/FormData → multipart/form-data

- [x] Task 2: Add response deserialization helpers
  - [x] getAndDecode, postAndDecode, putAndDecode, patchAndDecode
  - [x] getListAndDecode for list responses

- [x] Task 3: Write unit tests
  - [x] Test MultipartInterceptor behavior
  - [x] Test response deserialization

## Dev Notes

### Implementation Pattern

```dart
// JSON is default - no special method needed
await client.post('/users', data: {'name': 'John'});  // → application/json

// FormData auto-detected
await client.post('/upload', data: formData);  // → multipart/form-data

// Override content type globally
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  defaultContentType: 'text/xml',  // or null to disable
);

// Typed response with fromJson
final user = await client.postAndDecode('/users', body, User.fromJson);
```

### References

- [Source: epics.md#Story 3.3]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- ADR-010: JSON is now the default Content-Type (configurable)
- ADR-009: Created MultipartInterceptor for auto-detection of File
- ADR-011: ApiClientFactory pattern for client creation
- File/FormData auto-detected → multipart/form-data
- Removed postJson/putJson/patchJson (redundant)
- Kept *AndDecode methods for typed deserialization
- 10 unit tests for MultipartInterceptor

### File List

- `lib/src/client/api_client_config.dart` - Added defaultContentType
- `lib/src/client/multipart_interceptor.dart` - Auto-detect File → FormData
- `lib/src/client/api_client_factory.dart` - Factory for creating ApiClient
- `lib/src/client/api_client.dart` - Simplified, uses factory
- `test/client/multipart_interceptor_test.dart` - Unit tests

### Change Log

- 2026-03-16: Story 3.3 implemented - JSON requests/responses
- 2026-03-16: REFACTORED - JSON as default, auto-detect File/FormData
- 2026-03-16: Renamed ContentTypeInterceptor → MultipartInterceptor
- 2026-03-16: Added ApiClientFactory pattern (ADR-011)
