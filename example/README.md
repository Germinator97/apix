# Apix Example

A minimal example demonstrating basic usage of the **apix** package.

This list used to tag each entry with the release that introduced it, and it
stopped at `v2.3.0` while the package reached 5.x — a per-release relevé kept by
hand records the releases someone remembered, not what the file shows. It now
describes `example.dart` as it stands; the release something came from is a line
in the CHANGELOG.

See `example.dart` for:

- **SecureTokenProvider** — secure token storage with `flutter_secure_storage`
- **Simplified refresh flow** — auto token refresh with `refreshEndpoint`
- API client creation with `ApiClientFactory`
- Retry interceptor configuration, `respectRetryAfter` included
- Method-aware retry: idempotent methods only by default (`retryableMethods`),
  with a per-request `forceRetry()` opt-in for a POST protected by an
  `Idempotency-Key`
- Cache interceptor with strategies, and `varyHeaders` scoping entries to the
  caller
- Logger interceptor with header redaction
- Typed response deserialization (3 levels: standard / parse-decode / data)
- A binary download with `getAndReadBytes`: the bytes with their headers and
  file name, checked against `expectedContentTypes`
- Error handling with `Result` type and typed `ApiException`
- Automatic `DioException` → `ApiException` transformation
- Token management (save, clear, storage access)
- Catching `ParsingException`, `TokenProviderException`,
  `UnexpectedContentTypeException`, `MultipartReplayException`
- Opt-in `strictContentType` for captive-portal detection
- `responseValidator` hook for legacy APIs that signal errors via HTTP 200 with
  `{"success": false, ...}` (commented in the example)
- **`SecureStorageService.onBeforeRecoveryDelete`** — the one place apix
  destroys a credential without being asked, announced before it happens
- **`SecureStorageService.classify` / `SecureStorageFailure`** — telling an
  unreadable *entry*, which apix recovers from by dropping it, from an unusable
  *store*, which it rethrows because nothing in it can be read, written or even
  deleted

## Full Example App

For a complete runnable Flutter app with all features (auth, Sentry, metrics),
see the `apix_example_app` project in the parent directory. Its home screen runs
a probe per defect the package has closed, against scripted adapters. (No count
here on purpose: a number written in prose describes the day it was typed.)
