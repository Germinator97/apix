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
  - SentryInterceptor for error reporting
  - Result pattern for functional error handling
