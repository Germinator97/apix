# Story 8.3: Create Example App

Status: needs-update

> **Note:** Requires update after Epic 9 (SecureTokenProvider) implementation to document:
> - SecureStorageService
> - SecureTokenProvider
> - AuthConfig new fields (refreshEndpoint, refreshHeaders, onTokenRefreshed)

## Story

As a developer,
I want a working example app,
So that I can see apix in action.

## Acceptance Criteria

1. **Given** the example/ folder
   **Then** it contains a runnable Flutter app

2. **Given** the example app
   **Then** demonstrates all major features (auth, retry, cache)

3. **Given** the example code
   **Then** includes comments explaining each feature

## Tasks / Subtasks

- [x] Task 1: Create example project structure
  - [x] pubspec.yaml with dependencies
  - [x] README.md with documentation

- [x] Task 2: Implement API Service
  - [x] ApiClientFactory usage
  - [x] AuthInterceptor configuration
  - [x] RetryInterceptor configuration
  - [x] CacheInterceptor configuration
  - [x] LoggerInterceptor configuration
  - [x] MetricsInterceptor configuration
  - [x] API methods with models

- [x] Task 3: Implement TokenStorage
  - [x] TokenProvider implementation
  - [x] flutter_secure_storage integration

- [x] Task 4: Create Demo UI
  - [x] Basic GET request demo
  - [x] Result type demo
  - [x] Cache-first demo
  - [x] Force refresh demo
  - [x] Clear cache demo
  - [x] POST request demo

- [x] Task 5: Add comprehensive comments
  - [x] Section headers
  - [x] Feature explanations
  - [x] Usage examples

## Dev Notes

### Features Demonstrated

1. **API Client Setup** - Full configuration with factory
2. **Authentication** - TokenProvider + AuthInterceptor
3. **Retry Logic** - RetryConfig with exponential backoff
4. **Caching** - NetworkFirst + CacheFirst strategies
5. **Logging** - LoggerInterceptor with redaction
6. **Metrics** - MetricsInterceptor with callbacks
7. **Error Handling** - Result type for functional approach

### Project Structure

```
example/
├── lib/
│   ├── main.dart
│   ├── api/
│   │   ├── api_service.dart
│   │   └── token_storage.dart
│   └── screens/
│       └── home_screen.dart
├── pubspec.yaml
└── README.md
```

### API Used

JSONPlaceholder (https://jsonplaceholder.typicode.com/)
- Free fake REST API
- No authentication required
- Perfect for demos

### References

- [Source: epics.md#Story 8.3]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Completion Notes List

- Full Flutter example app
- All interceptors demonstrated
- Comprehensive comments
- README with code examples

### File List

- `example/pubspec.yaml`
- `example/README.md`
- `example/lib/main.dart`
- `example/lib/api/api_service.dart`
- `example/lib/api/token_storage.dart`
- `example/lib/screens/home_screen.dart`

### Change Log

- 2026-03-17: Story 8.3 implemented - example app created
