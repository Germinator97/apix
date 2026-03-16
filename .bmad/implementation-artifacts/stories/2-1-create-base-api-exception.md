# Story 2.1: Create Base ApiException

Status: done

## Story

As a developer,
I want a base ApiException class,
so that all API errors have a common type to catch.

## Acceptance Criteria

1. **Given** an API error occurs
   **When** I catch ApiException
   **Then** I have access to message, statusCode, and originalError

2. **Given** an ApiException is thrown
   **When** I call toString()
   **Then** I get a clear, readable representation

## Tasks / Subtasks

- [x] Task 1: Create ApiException class (AC: #1, #2)
  - [x] Create `lib/src/errors/api_exception.dart`
  - [x] Implement message, statusCode, originalError properties
  - [x] Implement toString() method
  - [x] Export from barrel file

- [x] Task 2: Write unit tests (AC: #1, #2)
  - [x] Create `test/errors/api_exception_test.dart`
  - [x] Test constructor and properties
  - [x] Test toString() output

## Dev Notes

### Architecture Requirements

**From ADR-004:**
```dart
ApiException (base)
├── NetworkException
│   ├── TimeoutException
│   └── ConnectionException
├── HttpException
│   ├── ClientException (4xx)
│   └── ServerException (5xx)
└── AuthException
    ├── UnauthorizedException (401)
    └── ForbiddenException (403)
```

### Implementation Pattern

```dart
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Object? originalError;
  
  const ApiException({
    required this.message,
    this.statusCode,
    this.originalError,
  });
  
  @override
  String toString() => 'ApiException: $message${statusCode != null ? ' (status: $statusCode)' : ''}';
}
```

### References

- [Source: architecture.md#ADR-004]
- [Source: epics.md#Story 2.1]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Created ApiException base class with message, statusCode, originalError, stackTrace
- Added equality operators and hashCode
- 8 unit tests passing

### File List

- `lib/src/errors/api_exception.dart` - Base exception class
- `lib/apix.dart` - Updated barrel export
- `test/errors/api_exception_test.dart` - Unit tests

### Change Log

- 2026-03-16: Story 2.1 implemented - ApiException base class
