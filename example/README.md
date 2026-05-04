# Apix Example

A minimal example demonstrating basic usage of the **apix** package.

See `example.dart` for:

- **SecureTokenProvider** - Secure token storage with `flutter_secure_storage`
- **Simplified refresh flow** - Auto token refresh with `refreshEndpoint`
- API client creation with `ApiClientFactory`
- Retry interceptor configuration (with `respectRetryAfter`, v2.1.0+)
- Cache interceptor with strategies
- Logger interceptor with header redaction
- Typed response deserialization (3 levels: standard / parse-decode / data)
- Error handling with `Result` type and typed `ApiException`
- Automatic `DioException` → `ApiException` transformation
- Token management (save, clear, storage access)
- **(v2.1.0)** Catching `ParsingException`, `TokenProviderException`,
  `UnexpectedContentTypeException`
- **(v2.1.0)** Opt-in `strictContentType` for captive-portal detection
- **(v2.1.0)** `responseValidator` hook for legacy APIs that signal errors
  via HTTP 200 with `{"success": false, ...}` (commented in the example)

## Full Example App

For a complete runnable Flutter app with all features (auth, Sentry, metrics),
see the `apix_example_app` project in the parent directory.
