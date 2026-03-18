# Story 5.3: Implement Exponential Backoff

Status: done

## Story

As a developer,
I want exponential backoff between retries,
so that I don't overwhelm failing servers.

## Acceptance Criteria

1. **Given** retry is triggered
   **When** waiting between attempts
   **Then** delay follows exponential backoff (e.g., 1s, 2s, 4s)

2. **Given** I need custom backoff
   **Then** I can configure base delay and multiplier

## Tasks / Subtasks

- [x] Task 1: Implemented in Story 5-1
  - [x] baseDelayMs parameter (default: 1000)
  - [x] multiplier parameter (default: 2.0)
  - [x] getDelay(attempt) calculates backoff
  - [x] Unit tests for backoff calculation

## Dev Notes

### Implementation (from Story 5-1)

```dart
const config = RetryConfig(
  baseDelayMs: 1000,  // 1 second base
  multiplier: 2.0,    // double each time
);

// Delays: 1s → 2s → 4s → 8s
config.getDelay(0); // 1000ms
config.getDelay(1); // 2000ms
config.getDelay(2); // 4000ms
config.getDelay(3); // 8000ms
```

### References

- [Source: epics.md#Story 5.3]
- Implemented as part of Story 5.1

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- Functionality delivered in Story 5-1
- baseDelayMs and multiplier fully configurable
- getDelay() calculates exponential backoff
- Tests verify 1s, 2s, 4s progression

### File List

- `lib/src/retry/retry_config.dart` - Contains getDelay()
- `test/retry/retry_interceptor_test.dart` - Backoff tests

### Change Log

- 2026-03-17: Story 5.3 marked done - Already implemented in 5-1
