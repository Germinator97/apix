# Story 7.1: Implement LoggerInterceptor

Status: done

## Story

As a developer,
I want requests/responses logged in dev mode,
So that I can debug API calls easily.

## Acceptance Criteria

1. **Given** LoggerConfig is enabled
   **Then** requests log method, URL, headers, body

2. **Given** response received
   **Then** responses log status, duration, body

3. **Given** release mode
   **Then** logging is disabled by default

## Tasks / Subtasks

- [x] Task 1: Create LoggerConfig class
  - [x] LogLevel enum (none, error, warning, info, debug)
  - [x] LogEntry structured data class
  - [x] Configuration options (enabled, level, logHeaders, logBody)
  - [x] Header redaction for sensitive data
  - [x] Body truncation for large payloads

- [x] Task 2: Create LoggerInterceptor
  - [x] Log requests (method, URL, headers, body)
  - [x] Log responses (status, duration, body)
  - [x] Log errors (type, message, response)
  - [x] Track request duration

- [x] Task 3: Write unit tests
  - [x] LogLevel tests
  - [x] LogEntry tests
  - [x] LoggerConfig tests
  - [x] LoggerInterceptor tests

## Dev Notes

### Usage Examples

```dart
// Default logging
final dio = Dio();
dio.interceptors.add(LoggerInterceptor());

// Debug mode (verbose)
dio.interceptors.add(LoggerInterceptor(
  config: LoggerConfig.debug(),
));

// Minimal (errors only)
dio.interceptors.add(LoggerInterceptor(
  config: LoggerConfig.minimal(),
));

// Custom log handler
dio.interceptors.add(LoggerInterceptor(
  config: LoggerConfig(
    logHandler: (entry) {
      myLogger.log(entry.level.name, entry.message);
    },
  ),
));
```

### LogEntry Structure

```dart
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? method;
  final String? url;
  final int? statusCode;
  final int? durationMs;
  final Map<String, dynamic>? headers;
  final dynamic body;
  final Object? error;
  final Map<String, dynamic>? extra;
}
```

### References

- [Source: epics.md#Story 7.1]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- LogLevel enum with 5 levels
- LogEntry structured log data
- LoggerConfig with factory constructors
- Header redaction for sensitive headers
- Body truncation for large payloads
- Duration tracking via request extension
- 31 tests

### File List

- `lib/src/logging/logger_config.dart` - Config and LogEntry
- `lib/src/logging/logger_interceptor.dart` - Interceptor
- `lib/apix.dart` - Exports
- `test/logging/logger_interceptor_test.dart` - Unit tests

### Change Log

- 2026-03-17: Story 7.1 implemented - LoggerInterceptor
