# Story 2.3: Create HTTP Exception Hierarchy

Status: done

## Story

As a developer,
I want typed HTTP exceptions (Client 4xx, Server 5xx),
so that I can handle HTTP errors granularly.

## Acceptance Criteria

1. **Given** a 4xx HTTP response is received
   **When** the error is mapped
   **Then** ClientException is thrown (UnauthorizedException for 401, ForbiddenException for 403)

2. **Given** a 5xx HTTP response is received
   **When** the error is mapped
   **Then** ServerException is thrown
   **And** both extend HttpException which extends ApiException

## Tasks / Subtasks

- [x] Task 1: Create HttpException class (AC: #1, #2)
  - [x] Create `lib/src/errors/http_exception.dart`
  - [x] Extend ApiException
  - [x] Add response body property

- [x] Task 2: Create ClientException hierarchy (AC: #1)
  - [x] Create ClientException (4xx)
  - [x] Create UnauthorizedException (401)
  - [x] Create ForbiddenException (403)
  - [x] Create NotFoundException (404)

- [x] Task 3: Create ServerException (AC: #2)
  - [x] Extend HttpException for 5xx errors

- [x] Task 4: Write unit tests
  - [x] Test inheritance hierarchy
  - [x] Test status codes
  - [x] Test toString() for each type

## Dev Notes

### Architecture Requirements

**From ADR-004:**
```dart
ApiException (base)
├── HttpException
│   ├── ClientException (4xx)
│   │   ├── UnauthorizedException (401)
│   │   ├── ForbiddenException (403)
│   │   └── NotFoundException (404)
│   └── ServerException (5xx)
```

### References

- [Source: architecture.md#ADR-004]
- [Source: epics.md#Story 2.3]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Created HttpException with responseBody property
- Created ClientException (4xx) with Unauthorized, Forbidden, NotFound
- Created ServerException (5xx)
- 23 unit tests passing

### File List

- `lib/src/errors/http_exception.dart` - HTTP exception hierarchy
- `lib/apix.dart` - Updated barrel export
- `test/errors/http_exception_test.dart` - Unit tests

### Change Log

- 2026-03-16: Story 2.3 implemented - HTTP exception hierarchy
