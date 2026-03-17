# Story 5.2: Configure Retry Status Codes

Status: done

## Story

As a developer,
I want to specify which HTTP codes trigger retry,
so that I control retry behavior.

## Acceptance Criteria

1. **Given** retryStatusCodes is configured (default: [500, 502, 503, 504])
   **When** response matches these codes
   **Then** retry is triggered

2. **Given** I need custom retry codes
   **Then** I can customize the list via RetryConfig

## Tasks / Subtasks

- [x] Task 1: Implemented in Story 5-1
  - [x] retryStatusCodes parameter in RetryConfig
  - [x] Default value [500, 502, 503, 504]
  - [x] shouldRetry(statusCode) helper method
  - [x] Unit tests for status code filtering

## Dev Notes

### Implementation (from Story 5-1)

```dart
// Default retry codes
const config = RetryConfig();
// retryStatusCodes: [500, 502, 503, 504]

// Custom retry codes
const customConfig = RetryConfig(
  retryStatusCodes: [500, 502, 503, 504, 429], // + rate limit
);

// Check if code triggers retry
config.shouldRetry(500); // true
config.shouldRetry(404); // false
```

### References

- [Source: epics.md#Story 5.2]
- Implemented as part of Story 5.1

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- Functionality delivered in Story 5-1
- retryStatusCodes fully configurable
- Tests already cover this functionality

### File List

- `lib/src/retry/retry_config.dart` - Contains retryStatusCodes
- `test/retry/retry_interceptor_test.dart` - Tests for status codes

### Change Log

- 2026-03-17: Story 5.2 marked done - Already implemented in 5-1
