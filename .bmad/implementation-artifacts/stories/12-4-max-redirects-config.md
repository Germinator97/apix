# Story 12.4: Add maxRedirects config and circular redirect detection

Status: ready-for-dev

## Story

As a developer,
I want explicit control over `maxRedirects` and detection of circular redirects (`A → B → A`),
so that misconfigured or malicious backends can't hang my app indefinitely or burn CPU/network.

## Context (why)

Brainstorming `[Fail #12]`: *"Redirect infini → maxRedirects config"*. Today we rely on Dio's default redirect handling — which is reasonable but not exposed in `ApiClientConfig`, and Dio's circular-redirect detection has been known to be incomplete in past versions.

## Acceptance Criteria

1. **Given** `ApiClientConfig(maxRedirects: 5)` (default)
   **When** a request is redirected
   **Then** up to 5 redirects are followed
   **And** the 6th redirect throws `TooManyRedirectsException` (extends `NetworkException`)

2. **Given** redirect chain `A → B → C → A`
   **When** the cycle back to A is detected
   **Then** `CircularRedirectException` (extends `NetworkException`) is thrown
   **And** the `chain` field exposes the visited URLs in order

3. **Given** `maxRedirects: 0`
   **Then** no redirects are followed (302/301 returned as-is — caller handles)

4. **Given** `followRedirects: false` (existing Dio option)
   **Then** behavior unchanged

5. **Given** redirects to a different host
   **When** the request includes `Authorization` header
   **Then** the `Authorization` header is **stripped** before redirecting (security — prevent leaking tokens to redirect targets)
   **And** an info-level log entry is produced if logger is enabled

## Tasks / Subtasks

- [ ] Task 1: Define exceptions
  - [ ] `TooManyRedirectsException(maxRedirects, chain)` extends `NetworkException`
  - [ ] `CircularRedirectException(chain)` extends `NetworkException`
  - [ ] Both expose `chain: List<Uri>`

- [ ] Task 2: Add `maxRedirects` to `ApiClientConfig`
  - [ ] Default: `5`
  - [ ] Update `copyWith`

- [ ] Task 3: `RedirectInterceptor` (or hook into existing pipeline)
  - [ ] New file `lib/src/client/redirect_interceptor.dart`
  - [ ] Track redirect chain per-request via `RequestOptions.extra`
  - [ ] On 301/302/303/307/308: validate cycle + count, then re-issue request
  - [ ] Strip `Authorization` header on cross-host redirects
  - [ ] Configure `Dio`'s `followRedirects: false` to take control

- [ ] Task 4: Wire into `ApiClientFactory`
  - [ ] Add to chain near the start (so it sees responses before logger/cache)

- [ ] Task 5: Unit tests
  - [ ] Linear redirect chain ≤ `maxRedirects` → success
  - [ ] Linear chain > `maxRedirects` → `TooManyRedirectsException`
  - [ ] Circular `A → B → A` → `CircularRedirectException`, `chain` correct
  - [ ] Cross-host redirect with `Authorization` → header stripped on second hop
  - [ ] `maxRedirects: 0` → first redirect surfaced as response (no follow)
  - [ ] Same-host redirect → `Authorization` preserved

## Dev Notes

### Why a custom interceptor (not just Dio's `maxRedirects`)

- Dio's `maxRedirects` exists but doesn't surface a typed exception we can catch
- We need to inject our `Authorization`-stripping logic on cross-host hops (security requirement)
- Centralizing this lets us also feed the redirect chain into `MetricsInterceptor` for observability

### Implementation pattern

```dart
class RedirectInterceptor extends Interceptor {
  static const _chainKey = 'apix_redirect_chain';
  final int maxRedirects;

  RedirectInterceptor({required this.maxRedirects});

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final code = response.statusCode ?? 0;
    if (![301, 302, 303, 307, 308].contains(code)) {
      handler.next(response);
      return;
    }
    final location = response.headers.value('location');
    if (location == null) {
      handler.next(response);
      return;
    }
    final chain = (response.requestOptions.extra[_chainKey] as List<Uri>?) ?? [];
    final next = response.requestOptions.uri.resolve(location);

    if (chain.length >= maxRedirects) {
      handler.reject(DioException(
        requestOptions: response.requestOptions,
        error: TooManyRedirectsException(
          maxRedirects: maxRedirects,
          chain: [...chain, next],
        ),
      ));
      return;
    }
    if (chain.contains(next)) {
      handler.reject(DioException(
        requestOptions: response.requestOptions,
        error: CircularRedirectException(chain: [...chain, next]),
      ));
      return;
    }
    // Strip Authorization on cross-host
    final headers = Map<String, dynamic>.from(response.requestOptions.headers);
    if (next.host != response.requestOptions.uri.host) {
      headers.remove('Authorization');
      headers.remove('authorization');
    }
    // Re-issue
    final newOptions = response.requestOptions.copyWith(
      path: next.toString(),
      headers: headers,
      extra: {...response.requestOptions.extra, _chainKey: [...chain, next]},
    );
    // ... fetch and resolve/reject
  }
}
```

### References

- Brainstorming `[Fail #12]`
- RFC 7231 §7.1.2 — Location header semantics
- OWASP guidance on `Authorization` leaking in redirects

## Dev Agent Record

### File List (Target)

- `lib/src/errors/network_exception.dart` — add the two new subclasses (or new files)
- `lib/src/client/redirect_interceptor.dart` — new
- `lib/src/client/api_client_config.dart` — add `maxRedirects`
- `lib/src/client/api_client_factory.dart` — wire
- `test/client/redirect_interceptor_test.dart` — new
