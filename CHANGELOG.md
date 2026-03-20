## 1.2.0

### Added

* **`ErrorMapperInterceptor`** - Automatically transforms `DioException` into typed `ApiException` subclasses
  - Timeout errors → `TimeoutException`
  - Connection errors → `ConnectionException`
  - HTTP 401 → `UnauthorizedException`
  - HTTP 403 → `ForbiddenException`
  - HTTP 404 → `NotFoundException`
  - Other HTTP errors → `HttpException`
  - Message extracted from response body (`message`, `error`, `detail`, `error_description`)
  - Added automatically to all clients created via `ApiClientFactory`

### Changed

* **Dependencies updated** for latest versions compatibility:
  - `dio`: `>=5.4.0 <7.0.0` (was `>=5.0.0`)
  - `sentry_flutter`: `>=9.0.0 <10.0.0` (was `>=8.0.0`)
  - `flutter_secure_storage`: `>=10.0.0 <11.0.0` (was `>=9.0.0`)
* **`SecureStorageService`** - Uses new secure defaults (RSA OAEP + AES-GCM) on Android
* **`SentrySetup`** - Updated for sentry_flutter 9.x API compatibility

---

## 1.1.0

### Added

* **`authConfig` parameter** in `ApiClientFactory.create` - Configure authentication directly
* **`retryConfig` parameter** in `ApiClientFactory.create` - Configure retry logic directly
* **`cacheConfig` parameter** in `ApiClientFactory.create` - Configure caching directly
* **`loggerConfig` parameter** in `ApiClientFactory.create` - Configure logging directly
* **`errorTrackingConfig` parameter** in `ApiClientFactory.create` - Configure error tracking directly (Sentry, Crashlytics, etc.)
* **`metricsConfig` parameter** in `ApiClientFactory.create` - Configure request metrics directly

### Changed

* Renamed `captureException` → `onError`, `addBreadcrumb` → `onBreadcrumb`
* Updated README documentation to match actual API signatures

---

## 1.0.0

### 🎉 First Stable Release

ApiX is now production-ready with a complete feature set for Flutter/Dart API clients.

### Features

* **Core API Client** - Dio-powered client with configurable timeouts, headers, and interceptors
* **Authentication** - TokenProvider interface with refresh token queue and automatic retry
* **Secure Token Storage** - Built-in SecureTokenProvider with flutter_secure_storage
* **Retry Logic** - Exponential backoff with configurable status codes and max attempts
* **Smart Caching** - CacheFirst, NetworkFirst, and HTTP-aware strategies with TTL
* **Observability** - Logger, Metrics, and Sentry interceptors for debugging and monitoring
* **Result Pattern** - Functional error handling with Success/Failure types
* **Exception Hierarchy** - NetworkException, HttpException, and typed client/server errors

### Highlights

* 401 tests passing
* Full API documentation
* Example app included
* CI/CD with GitHub Actions

---

## 0.3.0

### Added
* **SecureStorageService**: Wrapper for `flutter_secure_storage` with simplified API
  - `write(key, value)`, `read(key)`, `delete(key)`, `deleteAll()`
  - `containsKey(key)`, `readAll()`
  - Default secure options for Android and iOS
  - Injectable `FlutterSecureStorage` for custom configuration

* **SecureTokenProvider**: Ready-to-use `TokenProvider` implementation
  - Zero-boilerplate token management
  - Configurable storage keys (`accessTokenKey`, `refreshTokenKey`)
  - Exposed `storage` getter for secondary usage (Firebase tokens, API keys)
  - Works with `SecureStorageService` via composition

* **Simplified Token Refresh**: New `refreshEndpoint` approach in `AuthConfig`
  - `refreshEndpoint`: Relative URL for automatic refresh calls
  - `refreshHeaders`: Optional custom headers for refresh request
  - `onTokenRefreshed`: Callback with raw `Response` for parsing
  - `refreshTokenBodyKey`: Configurable body key (default: 'refresh_token')
  - `hasSimplifiedRefresh`: Getter to check if simplified flow is configured

### Changed
* `AuthInterceptor` now supports both simplified and legacy refresh flows
* Simplified flow takes priority when `refreshEndpoint` is configured

### Backward Compatibility
* Existing `onRefresh` callback still works as before
* All new fields are optional with sensible defaults

## 0.0.1

* Initial release with core features:
  - ApiClient with configurable timeouts and interceptors
  - TokenProvider interface for authentication
  - AuthInterceptor with refresh token queue
  - RetryInterceptor with exponential backoff
  - CacheInterceptor with multiple strategies
  - LoggerInterceptor for debugging
  - ErrorTrackingInterceptor for error reporting
  - Result pattern for functional error handling
