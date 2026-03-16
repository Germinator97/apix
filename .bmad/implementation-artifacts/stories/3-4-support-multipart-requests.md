# Story 3.4: Support Multipart Requests

Status: done

## Story

As a developer,
I want to send multipart/form-data requests,
so that I can upload files.

## Acceptance Criteria

1. **Given** a file to upload
   **When** I call client.post with File in data Map
   **Then** MultipartInterceptor auto-detects the File
   **And** Converts to FormData automatically
   **And** Sets Content-Type to multipart/form-data

2. **Given** FormData or File in data
   **Then** files are properly encoded as MultipartFile

## Tasks / Subtasks

- [x] Task 1: Auto-detect File for multipart (ADR-009)
  - [x] MultipartInterceptor detects File, List<File>, Map<String, File>
  - [x] Converts to FormData with MultipartFile automatically
  - [x] Sets Content-Type to multipart/form-data

- [x] Task 2: Use standard post() with File in data
  - [x] No special postMultipart/uploadFile methods needed
  - [x] Progress callbacks work with onSendProgress

- [x] Task 3: Write unit tests
  - [x] Test File auto-detection in MultipartInterceptor
  - [x] Test List<File> detection

## Dev Notes

### Implementation Pattern

```dart
// Just pass File in your data - interceptor handles the rest
await client.post('/upload', data: {
  'file': File('/path/to/image.jpg'),
  'name': 'my-image',
});  // → auto-converted to FormData, Content-Type: multipart/form-data

// Multiple files
await client.post('/upload', data: {
  'files': [file1, file2],
  'count': 2,
});

// With progress callback
await client.post(
  '/upload',
  data: {'file': myFile},
  onSendProgress: (sent, total) => print('$sent / $total'),
);

// FormData also supported directly
await client.post('/upload', data: formData);
```

### References

- [Source: epics.md#Story 3.4]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- ADR-009: MultipartInterceptor auto-detects File in Map data
- Detects File, List<File>, Map<String, File>
- Converts to FormData with MultipartFile automatically
- Removed postMultipart/putMultipart/uploadFile/uploadFiles (redundant)
- Use standard post() with File in data - simpler API
- 10 unit tests for MultipartInterceptor

### File List

- `lib/src/client/multipart_interceptor.dart` - Auto-detects File → FormData
- `test/client/multipart_interceptor_test.dart` - Tests File detection

### Change Log

- 2026-03-16: Story 3.4 implemented - Multipart requests
- 2026-03-16: REFACTORED - Auto-detect File in Map data
- 2026-03-16: Renamed ContentTypeInterceptor → MultipartInterceptor
