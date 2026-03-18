# Story 2.4: Implement Result Pattern

Status: done

## Story

As a developer,
I want .getResult() extension for functional error handling,
so that I can use Result pattern instead of exceptions.

## Acceptance Criteria

1. **Given** any Future<T> that may throw ApiException
   **When** I call .getResult()
   **Then** I get Future<Result<T, ApiException>>

2. **Given** a Result object
   **When** I check its state
   **Then** I can use isSuccess/isFailure to check state

3. **Given** a Result object
   **When** I want to handle both cases
   **Then** I can use fold() or when() for pattern matching

## Tasks / Subtasks

- [x] Task 1: Create Result class (AC: #1, #2, #3)
  - [x] Create `lib/src/models/result.dart`
  - [x] Implement Result.success() and Result.failure()
  - [x] Implement isSuccess/isFailure getters
  - [x] Implement fold() method
  - [x] Implement when() method

- [x] Task 2: Create getResult() extension (AC: #1)
  - [x] Create extension on Future<T>
  - [x] Catch ApiException and return Result.failure

- [x] Task 3: Write unit tests
  - [x] Test Result.success
  - [x] Test Result.failure
  - [x] Test fold() and when()
  - [x] Test getResult() extension

## Dev Notes

### Architecture Requirements

**From ADR-006:**
```dart
extension ResultExtension<T> on Future<T> {
  Future<Result<T, ApiException>> getResult() async {
    try {
      return Result.success(await this);
    } on ApiException catch (e) {
      return Result.failure(e);
    }
  }
}
```

### References

- [Source: architecture.md#ADR-006]
- [Source: epics.md#Story 2.4]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Created sealed Result class with Success/Failure subtypes
- Implemented fold(), when(), map(), mapAsync()
- Created getResult() extension on Future<T>
- 24 unit tests passing

### File List

- `lib/src/models/result.dart` - Result type and extension
- `lib/apix.dart` - Updated barrel export
- `test/models/result_test.dart` - Unit tests

### Change Log

- 2026-03-16: Story 2.4 implemented - Result pattern
