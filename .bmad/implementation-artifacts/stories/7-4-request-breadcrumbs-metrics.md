# Story 7.4: Request Breadcrumbs & Metrics

Status: done

## Story

As a developer,
I want request breadcrumbs and timing metrics,
So that I can track API performance.

## Acceptance Criteria

1. **Given** observability is enabled
   **Then** each request creates a breadcrumb with timing

2. **Given** request completes
   **Then** I can track request/response metrics (duration, status)

3. **Given** error occurs
   **Then** custom error reporters can access this context

## Tasks / Subtasks

- [x] Task 1: Create RequestMetrics class
  - [x] Request ID, method, URL, path
  - [x] Start/end time, duration
  - [x] Status code, success flag
  - [x] Error info
  - [x] Request/response size (optional)

- [x] Task 2: Create RequestBreadcrumb class
  - [x] Type (request, response, error)
  - [x] Message, category, timestamp
  - [x] Data map

- [x] Task 3: Create MetricsInterceptor
  - [x] Track in-flight requests
  - [x] Emit breadcrumbs on request/response/error
  - [x] Emit metrics on completion
  - [x] Custom request ID generator

- [x] Task 4: Write unit tests
  - [x] RequestMetrics tests
  - [x] RequestBreadcrumb tests
  - [x] MetricsConfig tests
  - [x] MetricsInterceptor tests (20 total)

## Dev Notes

### Usage Example

```dart
final dio = Dio();
dio.interceptors.add(MetricsInterceptor(
  config: MetricsConfig(
    onMetrics: (metrics) {
      // Send to analytics
      analytics.track('api_request', {
        'method': metrics.method,
        'path': metrics.path,
        'duration_ms': metrics.durationMs,
        'status_code': metrics.statusCode,
        'success': metrics.success,
      });
    },
    onBreadcrumb: (breadcrumb) {
      // Add to Sentry
      Sentry.addBreadcrumb(Breadcrumb(
        message: breadcrumb.message,
        category: breadcrumb.category,
        data: breadcrumb.data,
      ));
    },
  ),
));
```

### RequestMetrics Fields

- `requestId` - Unique identifier
- `method` - HTTP method
- `url` - Full URL
- `path` - Request path
- `startTime` - Request start
- `endTime` - Request end
- `durationMs` - Duration in ms
- `statusCode` - HTTP status
- `success` - Success flag
- `error` - Error message
- `errorType` - DioExceptionType
- `requestSize` - Request body size
- `responseSize` - Response body size

### BreadcrumbType

- `request` - Request started
- `response` - Response received
- `error` - Error occurred

### References

- [Source: epics.md#Story 7.4]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- RequestMetrics with full request context
- RequestBreadcrumb for tracking
- MetricsInterceptor with callbacks
- In-flight request tracking
- 20 tests

### File List

- `lib/src/observability/metrics_interceptor.dart` - Interceptor + Types
- `lib/apix.dart` - Export
- `test/observability/metrics_interceptor_test.dart` - 20 tests

### Change Log

- 2026-03-17: Story 7.4 implemented - MetricsInterceptor
