# Story 7.3: Implement SentryInterceptor

Status: done

## Story

As a developer,
I want Sentry error reporting built-in,
So that I don't have to implement it myself.

## Acceptance Criteria

1. **Given** SentryConfig with dsn and environment
   **Then** API errors are captured to Sentry

2. **Given** error occurs
   **Then** request context (URL, method, headers) is included

3. **Given** enabled flag is false
   **Then** no errors are captured

## Tasks / Subtasks

- [x] Task 1: Create SentryConfig
  - [x] enabled flag
  - [x] environment parameter
  - [x] captureException callback
  - [x] addBreadcrumb callback
  - [x] captureStatusCodes set (default: 5xx)
  - [x] Header redaction
  - [x] Body truncation

- [x] Task 2: Create SentryInterceptor
  - [x] Add request breadcrumbs
  - [x] Add response breadcrumbs
  - [x] Capture DioException errors
  - [x] Capture HTTP errors (5xx by default)
  - [x] Include request context

- [x] Task 3: Write unit tests
  - [x] SentryConfig tests
  - [x] SentryHttpException tests
  - [x] SentryInterceptor tests (17 total)

## Dev Notes

### Design Decision: Agnostic Callbacks

L'intercepteur n'a **pas de dépendance directe à Sentry SDK**.
Il utilise des callbacks génériques pour supporter:
- Sentry
- Crashlytics
- Bugsnag
- Custom error tracking

### Usage Example

```dart
// With Sentry SDK
final interceptor = SentryInterceptor(
  config: SentryConfig(
    environment: 'production',
    captureException: (exception, {stackTrace, extra, tags}) async {
      await Sentry.captureException(
        exception,
        stackTrace: stackTrace,
        withScope: (scope) {
          extra?.forEach((key, value) => scope.setExtra(key, value));
          tags?.forEach((key, value) => scope.setTag(key, value));
        },
      );
    },
    addBreadcrumb: (data) {
      Sentry.addBreadcrumb(Breadcrumb(
        message: data['message'] as String?,
        category: data['category'] as String?,
        data: data['data'] as Map<String, dynamic>?,
      ));
    },
  ),
));
```

### Error Context

Chaque erreur inclut:
- `method` - HTTP method
- `url` - Request URL
- `path` - Request path
- `headers` - Redacted headers
- `status_code` - HTTP status
- `request_body` - Optional
- `response_body` - Optional
- `environment` - Environment name

### Tags

- `http.method`
- `http.url`
- `http.status_code`
- `environment`

### References

- [Source: epics.md#Story 7.3]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- Framework-agnostic callbacks
- SentryHttpException for HTTP errors
- Request/response breadcrumbs
- 17 tests

### File List

- `lib/src/observability/sentry_interceptor.dart` - Interceptor + Config
- `lib/src/observability/sentry_setup.dart` - SentryFlutter initialization
- `lib/apix.dart` - Export
- `test/observability/sentry_interceptor_test.dart` - 17 tests
- `pubspec.yaml` - Added sentry_flutter dependency

### Change Log

- 2026-03-17: Story 7.3 implemented - SentryInterceptor
- 2026-03-17: Added SentrySetup for SentryFlutter initialization
