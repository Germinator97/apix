## 2.0.0

### Breaking

* **`ApiClient` methods now throw `ApiException` instead of `DioException`**
  - All HTTP methods (`get`, `post`, `put`, `delete`, `patch`) and typed variants unwrap `DioException` automatically
  - Code using `on DioException catch` on `ApiClient` methods must migrate to `on ApiException catch` (or subtypes)
  - `client.dio` (raw Dio access) still throws `DioException` — only `ApiClient` methods are affected
  - `getResult()` handles both `ApiException` and `DioException` (fallback for raw Dio usage)

### Fixed

* **`AuthInterceptor` — Refresh request isolation** (critical)
  - Refresh requests no longer inject the expired access token in the Authorization header
  - Refresh requests that return 401 no longer cause a deadlock (recursive refresh loop)
  - Auth-retried requests that fail again with 401 no longer trigger infinite refresh-retry loops

* **`ApiClient` methods now throw typed `ApiException` directly** (critical)
  - All HTTP methods (`get`, `post`, `put`, `delete`, `patch`) unwrap `DioException` automatically
  - `on ClientException catch`, `on UnauthorizedException catch`, etc. now work as expected
  - No need to catch `DioException` and extract `.error` manually
  - `getResult()` also works correctly with both `ApiException` and `DioException` (fallback for raw Dio usage)

* **`CacheInterceptor` — Cache key generation** (critical)
  - Fixed double-encoding of query parameters in cache keys
  - `invalidateUrl()` now resolves relative URLs against the client's base URL

* **`CacheInterceptor` — Deduplicated requests** (major)
  - Deduplicated requests now use the main Dio instance (with auth, logging, etc.) instead of a bare Dio that lost all interceptors

* **`ApiClient` — Null safety on response body** (major)
  - `*AndDecode` methods now throw `ApiException` instead of `TypeError` on null response body (e.g. 204 No Content)
  - `_extractData` now throws `ApiException` instead of `TypeError` on non-Map responses

* **`ErrorMapperInterceptor` — Nested error message extraction** (major)
  - Now extracts messages from nested error objects: `{ "error": { "message": "..." } }`
  - Supports common API formats: `error.message`, `error.detail`, `error.description`
  - `captureStatusCodes` filter now applies consistently in `onError` (previously only filtered in `onResponse`)

* **`MetricsInterceptor` — Request ID collisions** (moderate)
  - Uses monotonic counter instead of `_inFlight.length` for unique IDs
  - Adds orphan cleanup for entries older than 5 minutes

* **`SecureStorageService` — Corruption blast radius** (moderate)
  - `read()` and `containsKey()` now delete only the corrupted key instead of calling `deleteAll()`

* **Interceptor resilience** (moderate)
  - `AuthInterceptor`, `RetryInterceptor`, `CacheInterceptor` now wrap async `onRequest`/`onError`/`onResponse` in try/catch to prevent silent request hangs on unexpected exceptions

* **Sentry noise filter** (minor)
  - No longer accidentally filters out ApiX's own `TimeoutException`, `HttpException`, `ClientException`

### Added

* **`AuthConfig.onAuthFailure`** — Centralized callback when token refresh fails
  - Called exactly once per refresh attempt (even with concurrent requests queued)
  - Receives the error object for diagnostic: `onAuthFailure: (tokenProvider, error) async { ... }`
  - Use to clear tokens, redirect to login, or log the failure reason

* **`RetryConfig.maxDelayMs`** — Maximum delay cap for exponential backoff
  - Defaults to 30000ms (30 seconds)
  - Prevents overflow on high attempt counts

* **`InMemoryCacheStorage.maxEntries`** — Optional size limit with FIFO eviction

* **`CacheEntry.tryFromJson()`** — Null-safe factory for corrupted storage data

### Changed

* **`AuthException`** now extends `UnauthorizedException` (was `ApiException`)
  - Catchable with `on UnauthorizedException catch` alongside normal 401 errors
* **`OnAuthFailureCallback`** signature: `(TokenProvider, Object? error)` — includes the failure reason
* **Empty tokens** (`""`) are now ignored in `onRequest` and `_performSimplifiedRefresh`

---

## 1.4.0

### Added

* **`ApiClientConfig.dataKey`** - Configurable key for envelope unwrapping (default: `'data'`)
  - Used by all `*Data` methods to extract payload from `response.data[dataKey]`
  - Customizable per client: `ApiClientConfig(baseUrl: '...', dataKey: 'result')`

* **Data methods (envelope unwrapping)** - Extract and format `response.data[dataKey]` for envelope APIs
  - **GET single**: `getAndDecodeData`, `getAndDecodeDataOrNull`, `getAndParseData`, `getAndParseDataOrNull`
  - **GET list**: `getListAndDecodeData`, `getListAndDecodeDataOrNull`, `getListAndDecodeDataOrEmpty`, `getListAndParseData`, `getListAndParseDataOrNull`, `getListAndParseDataOrEmpty`
  - **POST single**: `postAndDecodeData`, `postAndDecodeDataOrNull`, `postAndParseData`, `postAndParseDataOrNull`
  - **POST list**: `postListAndDecodeData`, `postListAndDecodeDataOrNull`, `postListAndDecodeDataOrEmpty`, `postListAndParseData`, `postListAndParseDataOrNull`, `postListAndParseDataOrEmpty`

### Changed

* **`ApiClient` typed response methods redesigned** - 3 clear levels of response handling:
  - **Standard**: `get`, `post`, `put`, `delete`, `patch` → raw `Response<T>`
  - **Parse/Decode**: `{verb}AndParse`, `{verb}AndDecode` → format `response.data` (non-nullable, all verbs)
  - **Data**: `{verb}And{Parse|Decode}Data` → unwrap envelope then format (GET & POST only, with OrNull/List variants)

### Removed

* `getAndParseOrNull`, `getAndDecodeOrNull` - Replaced by `getAndParseDataOrNull`, `getAndDecodeDataOrNull`
* `postAndParseOrNull`, `postAndDecodeOrNull` - Replaced by `postAndParseDataOrNull`, `postAndDecodeDataOrNull`
* `getListAndDecode`, `getListAndParse` - Replaced by `getListAndDecodeData`, `getListAndParseData`
* `getListAndDecodeOrNull`, `getListAndDecodeOrEmpty` - Replaced by `getListAndDecodeDataOrNull`, `getListAndDecodeDataOrEmpty`
* `getListAndParseOrNull`, `getListAndParseOrEmpty` - Replaced by `getListAndParseDataOrNull`, `getListAndParseDataOrEmpty`

---

## 1.3.0

### Added

* **`SecureStorageService.withBiometrics()`** - Factory constructor for biometric-protected storage
  - iOS: Face ID / Touch ID via `userPresence` access control flag
  - Android: Biometric-backed encryption via `AndroidOptions.biometric()` (API 28+)
  - Customizable prompt titles for Android

* **`SentrySetup.addBreadcrumbFromMap()`** - Helper method for `ErrorTrackingConfig.onBreadcrumb`
  - Simplifies error tracking configuration to a single line
  - Example: `errorTrackingConfig: ErrorTrackingConfig(onError: SentrySetup.captureException, onBreadcrumb: SentrySetup.addBreadcrumbFromMap)`

* **`Result` functional methods** - Enhanced Result type with Either-like operations
  - `getOrElse(defaultValue)` - Returns value or default on failure
  - `flatMap(transform)` / `flatMapAsync` - Chains Result-returning operations
  - `mapError(transform)` - Transforms the error type
  - `recover(fallback)` - Recovers from failure with fallback value

* **`ApiClient` flexible parsing methods** - Support for any response type, not just JSON
  - `getAndParse(path, parser)` - Parse any response type (int, String, DateTime, etc.)
  - `putAndParse`, `patchAndParse` - PUT/PATCH variants
  - _Note: OrNull and List variants were redesigned in 1.4.0 as Data methods with envelope unwrapping_

### Fixed

* **`SecureStorageService`** - Auto-clear storage on bad padding exception
  - Handles corrupted encrypted data (e.g., after app reinstall or key rotation)
  - Affected methods: `read()`, `readAll()`, `containsKey()`
  - Returns safe defaults (`null`, `{}`, `false`) instead of throwing

---

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
