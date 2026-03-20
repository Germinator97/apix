# Apix Example

A minimal example demonstrating basic usage of the **apix** package.

See `example.dart` for:

- **SecureTokenProvider** - Secure token storage with `flutter_secure_storage`
- **Simplified refresh flow** - Auto token refresh with `refreshEndpoint`
- API client creation with `ApiClientFactory`
- Retry interceptor configuration
- Cache interceptor with strategies
- Logger interceptor with header redaction
- Typed response deserialization
- Error handling with `Result` type and typed `ApiException`
- Automatic `DioException` → `ApiException` transformation
- Token management (save, clear, storage access)

## Full Example App

For a complete runnable Flutter app with all features (auth, Sentry, metrics),
see the `apix_example_app` project in the parent directory.
