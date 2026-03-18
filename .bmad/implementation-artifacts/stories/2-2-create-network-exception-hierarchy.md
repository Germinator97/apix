# Story 2.2: Create Network Exception Hierarchy

Status: done

## Story

As a developer,
I want typed network exceptions (Timeout, Connection),
so that I can handle network issues specifically.

## Acceptance Criteria

1. **Given** a request timeout occurs
   **When** the error is mapped
   **Then** TimeoutException is thrown
   **And** it extends NetworkException which extends ApiException

2. **Given** a connection failure occurs
   **When** the error is mapped
   **Then** ConnectionException is thrown

## Tasks / Subtasks

- [x] Task 1: Create NetworkException class (AC: #1, #2)
  - [x] Create `lib/src/errors/network_exception.dart`
  - [x] Extend ApiException
  - [x] Export from barrel file

- [x] Task 2: Create TimeoutException class (AC: #1)
  - [x] Extend NetworkException
  - [x] Add timeout-specific properties (duration)

- [x] Task 3: Create ConnectionException class (AC: #2)
  - [x] Extend NetworkException
  - [x] Add connection-specific properties

- [x] Task 4: Write unit tests (AC: #1, #2)
  - [x] Create `test/errors/network_exception_test.dart`
  - [x] Test inheritance hierarchy
  - [x] Test toString() for each type

## Dev Notes

### Architecture Requirements

**From ADR-004:**
```dart
ApiException (base)
├── NetworkException
│   ├── TimeoutException
│   └── ConnectionException
```

### References

- [Source: architecture.md#ADR-004]
- [Source: epics.md#Story 2.2]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Created NetworkException extending ApiException
- Created TimeoutException with duration property
- Created ConnectionException
- 13 unit tests passing
- Hierarchy: ApiException → NetworkException → Timeout/Connection

### File List

- `lib/src/errors/network_exception.dart` - Network exception hierarchy
- `lib/apix.dart` - Updated barrel export
- `test/errors/network_exception_test.dart` - Unit tests

### Change Log

- 2026-03-16: Story 2.2 implemented - Network exception hierarchy
