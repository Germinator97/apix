## 5.0.0

Audit of the whole package: 29 defects, 17 reproduced against the real client.
None raised, logged or reddened a test — they lived at the junctions between
interceptors. Nothing below needs a code change on your side; two entries change
how much traffic and how many tracker events to expect.

### Breaking

* Cache entries are scoped to the caller — `CacheConfig.varyHeaders`, default
  `['Authorization']`. Two accounts on one device used to share every entry.
  A token refresh now invalidates the cache: vary on a stable identity header to
  avoid it, or `const []` to opt out.
* `LoggerConfig` no longer logs request and response bodies by default.
* `SentrySetupOptions.sendDefaultPii` defaults to `false`.
* Failures that reached no observer now do — expect a one-off rise in events.

### Added

* Every typed-method family on every verb: 12 shapes x 5 verbs, so
  `putAndDecodeData`, `deleteListAndParseDataOrEmpty` and the rest exist. GET
  and POST had 12 each, PUT and PATCH 2, DELETE none.
* `RequestOptions.forceRevalidate()`, `MultipartReplayException`,
  `CacheBodyEncoding`.

### Fixed

**Cache**

* Query parameters written into the path were dropped from the key, so
  `/users?page=1` and `?page=2` shared one entry.
* A cache hit changed the body's type: `text/plain` `12345` returned as an int,
  a binary download as `List<dynamic>`.
* A `304` served the body as stale and never restarted the TTL, so
  `httpCacheAware` revalidated forever.
* `no-cache` and `must-revalidate` were parsed and ignored.
* `invalidateUrl('/users')` also removed `/users-archived` and `/users/123`.
* Concurrent `FileCacheStorage` writes to one key raced on a shared temp file;
  eviction scanned the whole directory on every write.

**Multipart**

* Nested fields and files were dropped — `{'a': {'b': {'file': File}}}` sent an
  empty body and returned `200`.
* An upload failed outright after a token refresh or a retry (`FormData` is
  single-use), and its `StateError` replaced the server's status.

**Observability**

* A refresh failure reached no log and no tracker, and leaked its in-flight
  metric; only the internal refresh call was reported.
* A `responseValidator` rejection was recorded as a success, cached, then served
  unvalidated on the next hit.
* `ErrorMapperInterceptor` rewrote an already-typed exception unless it arrived
  with type `unknown`.
* A reused `RequestOptions` was observed only on its first execution.
* `profilesSampleRate` and both replay sample rates were accepted and ignored;
  `customBeforeSendTransaction` got an empty `Hint`; a failed `SentrySetup.init`
  blocked every later attempt.

**Client**

* A bare `[]` where an envelope was expected broke the `...OrEmpty` and
  `...OrNull` variants.
* `ApiException.code` no longer returns the HTTP status disguised as a business
  code — a value equal to the status is dropped, in either spelling. Reported by
  a consumer as a review point.
* `RetryConfig` broke the `==`/`hashCode` contract.
* `RetryInterceptor` swallowed failures of its own retry machinery.
* A post-refresh token read did not raise `TokenProviderException`.
* A hanging `onAuthFailure` froze the refresh queue.

## 4.1.0

Two rounds of the same defect, reported by a consumer and then found by
auditing for others like it: a `Future` completed with an error that nobody
listens to is reported to the zone — a Sentry event nobody can act on.

### Fixed

* **`RequestDeduplicator` no longer reports an unhandled error on every failed
  request.** Its `Completer` exists for duplicates that usually never arrive,
  so nothing listens to it — harmless on success, but `completeError` with no
  listener reports to the zone. Invisible until a `CancelToken` made
  cancellation routine. `DeduplicationInterceptor`, added in 4.0.0, shares that
  deduplicator, so the defect had just become reachable without a cache.
* **`ErrorTrackingConfig.onError` no longer leaks the same way.** Its `Future`
  was neither awaited nor ignored, so a tracker failing asynchronously reported
  an error nobody could receive — from inside the component whose job is
  receiving errors.
* **A failing observation callback no longer breaks the request.** A
  `logHandler`, `onMetrics`, `onBreadcrumb` or span starter that threw turned a
  `200` into an `ApiException` — an analytics backend having a bad minute
  failed the business request it was only observing.
* **A deduplicated request is observed once.** Outer and inner requests share a
  `CancelToken`, so a cancellation put the outer one through the error chain
  twice: one network call, two log lines, two tracker events.

### Changed

* Expect **fewer** events on the deduplicated error path — one per request
  instead of two. Nothing to change on your side; the counts in your dashboard
  drop by design.

### Docs

* `EncryptedCacheStorage.has()` can delete (it decrypts to answer, and purges
  what it cannot open), `AuthInterceptor` swallows a throwing `onAuthFailure`
  to avoid deadlocking the refresh queue, and `TooManyRequestsException
  .retryAfter` is populated regardless of `RetryConfig.respectRetryAfter`.

## 4.0.0

This release answers an integration report from a consumer, filed after moving a
wallet app onto 3.0.0. Eight gaps, none of which broke a build — three of them
were only findable by reading apix's source, which is why they survived the
last release.

The theme is the same throughout: apix knew something the consumer could not
reach. An error code it read past, a `Retry-After` it parsed and dropped, a
duration it measured and never reported.

### Migration at a glance

| If you… | Then… |
|---|---|
| catch `on ClientException` for a 429 | still works — `TooManyRequestsException` is a subtype. Read `retryAfter` to say *how long* to wait |
| assert an exact retry delay in a test | add `jitter: 0` — delays are now spread ±20 % by default |
| rely on `CacheStrategy.networkOnly` writing to your store | it no longer writes. If you were counting on that, use `networkFirst` |
| wrote a no-op `CacheStorage` just to get deduplication | delete it — pass `deduplicationConfig` and no `cacheConfig` |
| group Sentry issues by the type passed to `onError` | the `onResponse` path now sends `HttpTrackingException` **as an `HttpException`**. Existing issues may regroup |
| `import 'package:dio/dio.dart'` for `ResponseType`, `Interceptor`, `FormData`… | import `package:apix/apix.dart` instead; adapters live in `package:apix/testing.dart` |
| subclass `ApiException` with your own `code` field | **remove it** and pass `super.code` — a same-typed field now shadows the inherited one, and a differently-typed one (`int code`) will not compile |
| use none of the above | nothing to do |

### ⚠️ Breaking behavior

* **Retry delays are no longer deterministic.** `RetryConfig.jitter` defaults to
  `0.2`, spreading each computed backoff across ±20 % of itself.
  - Opt-in was the safer-looking choice and the wrong one: a thundering herd
    harms whoever did *not* read this changelog. After an outage, every client
    that failed in the same second used to retry at the same instants.
  - `jitter: 0.0` restores the previous sequence exactly. Any test asserting a
    precise delay needs it.
  - A server-named `Retry-After` is never jittered.

* **`CacheStrategy.networkOnly` no longer writes to the store.** It always
  documented "never read cache"; only the reading half was enforced, so every
  response was still written. On a wallet that moved balances and transactions
  through a store nobody ever read from.
  - The guard was missing from **two** write sites — `onResponse` and the
    deduplicated path — and a guard on the first alone still leaked on exactly
    the path a consumer enabling deduplication would take.

* **`ApiException` gained a `code` field**, which collides with any subclass
  that already declared one. Same type (`String`): the subclass shadows the
  inherited field and the analyzer warns. Different type (`int code`): it no
  longer compiles. Drop the field and forward `super.code` instead — this was
  found by rebuilding apix's own example app against 4.0.0, not by reading.

* **`HttpTrackingException` now extends `HttpException`.** The type handed to
  `ErrorTrackingConfig.onError` changes on the `onResponse` path, so trackers
  that group by runtime type may regroup existing issues.

### Added

* **`ApiException.code`** — the application error code, read from the response
  body under `errorCodeKey` (default `'code'`, configurable like `dataKey`).
  Branch on a stable business code instead of an HTTP status that drifts from
  `400` to `409` to `422` across server revisions. Always a `String`, even when
  the server sends a number; null on failures that have no body.

* **`TooManyRequestsException`** — a 429 with its parsed `retryAfter`, so the
  user can be told how long to wait instead of receiving the same generic
  message as for a malformed request.

* **`DeduplicationConfig` / `DeduplicationInterceptor`** — deduplication without
  a cache. `RequestDeduplicator` was only ever instantiated by
  `CacheInterceptor`, so getting one meant installing the other. When both are
  configured, the cache's own deduplication is switched off rather than
  collapsing each request twice.

* **`EncryptedCacheStorage`** — a decorator that seals body and headers before
  they reach any `CacheStorage`. You supply `encrypt`/`decrypt`, so apix takes
  on neither a crypto dependency nor your key. Cache keys stay in clear text —
  the invalidation API reads them — so keep identifiers out of URLs you cache.
  An entry that cannot be decrypted reads as a miss and is purged.

* **`TracingInterceptor` / `TracingConfig`** — one performance span per request,
  as a child of the current Sentry transaction. apix already measured duration,
  size and status; nothing ever opened a span, so durations could only land in a
  breadcrumb: visible after an incident, never aggregated.
  - One span covers the whole logical request, retries included.
  - A response served from cache opens none — it spent no time on the network.

* **`RetryInterceptor.onRetry`** — fires before each retry waits, carrying the
  attempt number, the delay and the cause. A retry storm used to be invisible:
  only the final failure surfaced.

* **`package:apix/testing.dart`** — `HttpClientAdapter`, `ResponseBody` and
  friends, so stubbing an adapter no longer forces a direct dio import (and with
  it, apix's dio version range) onto your test suite.

### Changed

* The dio barrel now also re-exports `ResponseType`, `RequestOptions`,
  `Interceptor` and its handlers, `DioException`, `DioExceptionType`,
  `FormData`, `MultipartFile` and `Headers` — derived from where apix's own API
  hands a dio type to a consumer. `create(interceptors:)` took a
  `List<Interceptor>` that could not be written without importing dio; binary
  downloads had no way to name `ResponseType`.

* `Retry-After` parsing moved to a shared helper used by both the retry
  interceptor and the error mapper, so what the caller is told to wait and what
  the interceptor actually waits cannot drift apart.

* The `onResponse` error-tracking path now attaches a stack trace. It had none,
  while the `onError` path always did.

## 3.0.0

This release is about the cache. Two of its promises were not kept: `cacheFirst`
did not refresh in the background despite saying so, and the TTL was only as
strong as whichever `CacheStorage` you plugged in. Both are now true. Error
tracking also stops flattening every failure into one `DioException`.

### Migration at a glance

| If you… | Then… |
|---|---|
| use `CacheStrategy.cacheFirst` | responses may now be **older than `defaultTtl`**. Check `response.isStale`, or move to `networkFirst` where freshness matters |
| call `CacheRequestExtension.isFromCache(response)` | replace with `response.isFromCache` |
| implement `CacheStorage` yourself | delete the expiry filter from `get` — keep it in `has` |
| inspect the argument of `ErrorTrackingConfig.onError` | it is the typed `ApiException` now, not a `DioException`. `e is DioException` stops matching **silently** — use `(e as ApiException).originalError` |
| catch `on ApiException` around a `cacheOnly` call | you will now actually catch `CacheException`; before, it slipped through |
| catch `on HttpException` for 4xx/5xx | still works — `ClientException` / `ServerException` are subtypes |
| use `SentrySetup` with `filterNetworkNoise` | your 5xx start reaching Sentry. Expect **more** events, not fewer — they were being dropped |
| use nothing but `networkFirst` (the default) | nothing to do |

### ⚠️ Breaking behavior

* **`CacheStrategy.cacheFirst` now serves stale data** — it does what it always
  documented: serve the cache immediately, refresh behind
  (stale-while-revalidate). An expired entry is returned, flagged `isStale`,
  while one background request renews it.
  - Network volume is unchanged: a fresh entry costs nothing, a stale one costs
    exactly one request — asserted by a test, not assumed. Only the waiting
    disappears.
  - **The risk to check**: a response may now be older than `defaultTtl`. Where
    that is unacceptable — an amount, a balance, an authorisation — use
    `networkFirst`, or surface `response.isStale`.
  - Other strategies are unaffected.

### Breaking

* **`ErrorTrackingConfig.onError` receives the typed `ApiException`**, not the
  raw `DioException`. Trackers group by runtime type, so a 500, a 404 and a
  timeout used to land in a single issue titled `DioException`. Nothing fails to
  compile; `e is DioException` just stops matching — reach the original through
  `(e as ApiException).originalError`.

* **`CacheRequestExtension.isFromCache(response)` removed** — use
  `response.isFromCache`. The old form was a static on an extension of
  `RequestOptions` taking a `Response`, so autocomplete never surfaced it.

* **`CacheStorage.get` must no longer filter on expiry** — only affects custom
  implementations. It returns entries expired or not; `null` means absent. The
  interceptor owns the TTL, so a backend can no longer weaken it by forgetting
  to filter. `has` keeps filtering.

### Added

* **`response.isFromCache` / `response.isStale`** — `isStale` is true wherever
  apix knowingly returns expired data: `cacheFirst` revalidating, and the
  offline fallback of `networkFirst` / `httpCacheAware`. **On an amount, a
  balance or a status, surface it.** A `304` is not stale. The underlying keys
  are exported as `fromCacheKey` / `fromCacheStaleKey`.

* **`FileCacheStorage`** — a cache that survives restarts, with **no new
  dependency**: one JSON file per entry, in a directory you supply.
  - **Bounded by default** (`maxEntries: 200`) — a process cache dies with the
    app, a disk cache does not. Expired entries are evicted first.
    `maxEntries: null` opts out.
  - Reads never throw (a corrupt file is a miss, and is discarded); writes are
    atomic; only its own files are touched.
  - ⚠️ Entries are stored **in clear text** — never point it at credentials,
    tokens, personal data or amounts.

### Fixed

* **`ClientException` and `ServerException` were never thrown** — `ErrorMapper`
  specialised only 401/403/404 and mapped everything else to a bare
  `HttpException`, leaving both clauses dead at every call site despite the
  documented hierarchy. Unspecialised 4xx now map to `ClientException`, 5xx to
  `ServerException`; other statuses stay `HttpException`. Not breaking — both
  are `HttpException` subtypes.

* **ApiX errors were discarded by ApiX's own Sentry filter** — `SentryException.type`
  is a bare class name, so the noise filter could not tell apix's
  `HttpException` from `dart:io`'s and **dropped every 5xx**. Classification is
  now by type hierarchy. Name matching is unchanged for everything else.

* **`CacheException` was not an `ApiException`** — a `cacheOnly` miss escaped
  the typed-error contract entirely, because `RequestInterceptorHandler.reject`
  skips the following error interceptors.

* **`cacheOnly` served expired entries** — it now rejects them, distinguishing a
  miss from an expiry.

* **Cache eviction ignored expiry** — `InMemoryCacheStorage` could drop a fresh
  entry while keeping a stale one.

---

## 2.3.0

### Changed

* **⚠️ BREAKING BEHAVIOR — Retry is now HTTP-method-aware; `POST` and `PATCH` are no longer retried by default**
  - Automatic retry previously replayed **any** request whose status code matched `retryStatusCodes`, ignoring the HTTP method. A `5xx` returned *after* the server had already committed (e.g. a gateway `502`/`504` timeout following a payment) would replay a non-idempotent request and produce a **duplicate** (double charge / double top-up).
  - `RetryInterceptor` now retries only requests whose method is in the new `RetryConfig.retryableMethods`, which defaults to the **idempotent** methods per RFC 7231 §4.2.2: `{GET, HEAD, OPTIONS, TRACE, PUT, DELETE}`. Method matching is case-insensitive.
  - **Migration** — if you relied on `POST`/`PATCH` being retried, either widen the set globally with `RetryConfig(retryableMethods: {...'POST'})`, or opt in **per request** (recommended) with `RequestOptions.forceRetry()` — see below.
  - Unchanged: no retry on a no-response network error (`statusCode == null`), `Retry-After` handling, and the per-request `disableRetry()` opt-out (still takes precedence).

### Added

* **`RetryConfig.retryableMethods`** — `Set<String>` of upper-case HTTP methods eligible for retry (default = idempotent methods)
  - Fully configurable: remove a method a backend mishandles, or add one you know is safe.

* **`RequestOptions.forceRetry()`** — per-request opt-in to retry a non-idempotent method
  - Overrides the method guard **only** — for a request that is provably safe to replay, typically a `POST`/`PATCH` protected by an `Idempotency-Key`.
  - Never overrides the no-response network guard, the status-code guard, or `maxAttempts`; `disableRetry()` still wins if both are set.
  - Symmetric counterpart of `disableRetry()`; backed by the exported `forceRetryKey` extra.

* **Dio `Options`, `CancelToken` and `Response` re-exported from the `apix` barrel** — no more direct `package:dio` import for common calls (`Options(extra: {noRetryKey: true})`, `cancelToken:`, typing a returned `Response<T>`, ...)

### Fixed

* **dio 5.10.0 compatibility across the declared `>=5.4.0 <7.0.0` range** — dio 5.10.0 introduced the `DioExceptionType.transformTimeout` enum value (breaking the exhaustive exception-mapping switches) and an optional parameter on `ErrorInterceptorHandler.reject`. Exception mapping now routes `transformTimeout` — and any future `DioExceptionType` — through its default branch (`ErrorMapperInterceptor` maps it to a generic `ApiException`; `AuthInterceptor` treats it as a non-network failure), so apix builds on both the floor and the latest of its declared dio range.

---

## 2.2.0

### Added

* **`SentrySetupOptions.configureOptions`** — Escape hatch for `SentryFlutterOptions` not exposed by apix
  - Callback `void Function(SentryFlutterOptions)` invoked **last** during `SentryFlutter.init`, after every apix default
  - Lets consumers enable Sentry options introduced in newer SDK versions without waiting for an apix release (e.g. `enableTombstone` in `sentry_flutter` 9.14+, `enableAppHangTrackingV2`, replay tuning)
  - Can override anything, including `beforeSend` / `beforeSendTransaction` — for composition that preserves apix's network-noise filter, prefer `customBeforeSend` / `customBeforeSendTransaction`
  - Exceptions thrown in the callback are swallowed in release builds and rethrown in debug, to avoid breaking app startup on a typo

---

## 2.1.0

### Fixed

* **`*AndDecode` / `*AndParse` — Parsing failures now surface as typed `ApiException`** (critical)
  - New `ParsingException` (extends `ApiException`) thrown when `fromJson` or a custom `parser` callback throws (e.g. truncated JSON, type mismatch)
  - Closes a gap in the 2.0.0 contract: `on ApiException catch` now catches **every** client-side parse failure
  - `originalError` and `stackTrace` are preserved
  - User-thrown `ApiException` from inside `fromJson`/`parser` is rethrown unchanged (no double-wrap)

* **`AuthInterceptor` — Network blip no longer logs the user out** (major)
  - When the refresh request fails with a connection / timeout error, the original request is rejected with `NetworkException` (typed: `ConnectionException`, `TimeoutException`)
  - `onAuthFailure` is **not** invoked on network failures
  - Real auth failures (401/403 from the refresh endpoint) still produce `AuthException` and call `onAuthFailure` (regression preserved)

* **`AuthInterceptor` — Token provider failures now typed** (moderate)
  - New `TokenProviderException(operation: read | write | clear)` (extends `ApiException`)
  - Wraps errors thrown by `getAccessToken`, `getRefreshToken`, and the user-supplied `onTokenRefreshed` callback
  - Surfaces directly to callers: `on TokenProviderException catch` distinguishes credential storage issues from network/HTTP errors

* **`AuthException` now preserves the underlying cause**
  - `AuthException(message, originalError: ..., stackTrace: ...)` — typed cause flows through to the caller via `originalError`

### Added

* **`RetryConfig.respectRetryAfter`** — Honor the server's `Retry-After` header on retryable responses (default `true`)
  - Parses both delta-seconds (`"60"`) and HTTP-date (`"Wed, 21 Oct 2026 07:28:00 GMT"`) formats per RFC 7231 §7.1.3
  - Capped at `RetryConfig.maxDelayMs`; falls back to exponential backoff if the header is absent or malformed
  - Public `RetryInterceptor.parseRetryAfter(value, {now})` exposed for advanced use and testing

* **`ApiClientConfig.strictContentType`** — Detect captive portals / wrong Content-Type (default `false`)
  - When `true`, `*AndDecode` methods verify the response's `Content-Type` starts with `application/json`
  - Throws `UnexpectedContentTypeException` (extends `ApiException`) on mismatch — exposes `expectedContentType` and `actualContentType` fields
  - `*AndParse` methods are unaffected (they accept any payload type by design)

* **`ApiClientConfig.responseValidator`** — Hook for legacy APIs that signal business errors via HTTP 200
  - `ResponseValidator` typedef: `ApiException? Function(Response)`
  - Returning a non-null exception fails the request with that typed exception; returning `null` lets the response pass through
  - Only fires on 2xx responses (4xx/5xx still go through `ErrorMapperInterceptor`)
  - Preserves the exact subclass returned (e.g. a custom `BusinessException`)

### Changed

* `*AndDecode` methods now use `<dynamic>` internally with explicit `_requireData` validation (instead of relying on Dio's eager generic cast)
  - Eliminates confusing `TypeError` on non-JSON responses; replaced by clear `ApiException` messages
  - `_requireData` now also throws `ApiException` when the body is non-null but not a `Map<String, dynamic>`

---

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
