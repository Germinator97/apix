# Story 10.1: Add Config Parameters to ApiClientFactory

## Status: Done

## Description

As a developer,
I want to configure auth, retry, cache, logger, and sentry via factory parameters,
So that I don't need to manually create and add interceptors.

## Acceptance Criteria

- [x] ApiClientFactory.create accepts authConfig parameter
- [x] ApiClientFactory.create accepts retryConfig parameter
- [x] ApiClientFactory.create accepts cacheConfig parameter
- [x] ApiClientFactory.create accepts loggerConfig parameter
- [x] ApiClientFactory.create accepts errorTrackingConfig parameter
- [x] Interceptors are added in correct order
- [x] All parameters are optional for backward compatibility
- [x] Tests pass

## Implementation

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  authConfig: AuthConfig(...),
  retryConfig: const RetryConfig(...),
  cacheConfig: CacheConfig(...),
  loggerConfig: const LoggerConfig(...),
  errorTrackingConfig: ErrorTrackingConfig(...),
  metricsConfig: MetricsConfig(...),
);
```

## Files Modified

- `lib/src/client/api_client_factory.dart`

## Completed

2026-03-19
