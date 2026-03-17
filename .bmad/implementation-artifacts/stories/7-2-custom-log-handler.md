# Story 7.2: Custom Log Handler

Status: done

## Story

As a developer,
I want to provide my own log handler,
So that I can integrate with my logging solution.

## Acceptance Criteria

1. **Given** custom logHandler in LoggerConfig
   **Then** all logs go through my handler

2. **Given** log event occurs
   **Then** I receive structured log data (not just strings)

## Tasks / Subtasks

- [x] Task 1: Verify LogHandler typedef exists
  - [x] `typedef LogHandler = void Function(LogEntry entry)`
  - [x] LogEntry contains all structured data

- [x] Task 2: Verify logHandler parameter in LoggerConfig
  - [x] Optional logHandler parameter
  - [x] Falls back to default print when null

- [x] Task 3: Write validation tests
  - [x] All logs go through custom handler
  - [x] Receives structured LogEntry
  - [x] Error logs include structured data
  - [x] Integration with external logging solutions

## Dev Notes

### Usage Example

```dart
// Custom log handler
final interceptor = LoggerInterceptor(
  config: LoggerConfig(
    logHandler: (LogEntry entry) {
      // entry.timestamp - DateTime
      // entry.level - LogLevel
      // entry.method - String?
      // entry.url - String?
      // entry.statusCode - int?
      // entry.durationMs - int?
      // entry.headers - Map?
      // entry.body - dynamic
      // entry.error - Object?
      // entry.extra - Map?
      
      myLogger.log(
        entry.level.name,
        '${entry.method} ${entry.url} [${entry.statusCode}]',
      );
    },
  ),
);
```

### LogEntry Structure

All fields available in structured LogEntry:
- `timestamp` - When the log was created
- `level` - LogLevel (none, error, warn, info, trace)
- `message` - Log message
- `method` - HTTP method
- `url` - Request URL
- `statusCode` - HTTP status code
- `durationMs` - Request duration
- `headers` - Request/response headers (redacted)
- `body` - Request/response body
- `error` - Error message/object
- `extra` - Additional context data

### References

- [Source: epics.md#Story 7.2]
- Built on Story 7.1 implementation

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- Already implemented in Story 7.1
- Added 4 dedicated validation tests
- Total: 35 logging tests

### File List

- `test/logging/logger_interceptor_test.dart` - Added Story 7.2 test group

### Change Log

- 2026-03-17: Story 7.2 validated - Custom Log Handler
