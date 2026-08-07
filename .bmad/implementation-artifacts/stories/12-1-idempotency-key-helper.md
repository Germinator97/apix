# Story 12.1: Add Idempotency-Key helper for write operations

Status: ready-for-dev

## Story

As a developer,
I want a built-in `idempotencyKey` parameter on `post`/`put`/`patch`/`delete` methods,
so that retries (after app crash, network blip, or `RetryInterceptor`) don't accidentally execute the same operation twice on the backend.

## Context (why)

Stripe, Square, Mollie and most modern payment APIs require an `Idempotency-Key` header. For the internal consumer apps backends, this is critical: a double-charge or double-transfer caused by a retry is a real-money bug. Today, developers must remember to set this header manually on every write call. ApiX should make it ergonomic.

Brainstorming reference: `[Fail #15] App killed mid-POST → Idempotency keys (doc)`. We go beyond doc — we provide a helper.

> ### ⚠️ Rewritten after apix 2.3.0 — read this before implementing
>
> This story was written **before** retry became method-aware. At the time,
> `RetryInterceptor` replayed any request whose status code matched, so an
> idempotency key was the *only* thing standing between a `502` and a double
> charge, and "the key survives the retry" was the whole point.
>
> Since 2.3.0 the picture is inverted: `RetryConfig.retryableMethods` defaults
> to the idempotent methods of RFC 7231 §4.2.2, so **apix does not replay
> `POST`/`PATCH` at all by default**. Setting an `Idempotency-Key` therefore
> **no longer causes anything to be retried** — implemented as originally
> specified, this helper would ship a header that changes nothing observable,
> and its acceptance criteria about "preserved across retries" would be
> untestable for the very methods it targets.
>
> The key now has two distinct jobs, and the story must serve both:
>
> 1. **Making `forceRetry()` safe.** `forceRetry()` is the deliberate opt-in
>    that puts a `POST` back in the replay budget. It is only defensible when
>    the server can de-duplicate — i.e. when a key is present. Key and opt-in
>    are now a **pair**.
> 2. **Replays apix never sees.** App killed mid-POST and relaunched, user
>    double-tapping, a proxy or the OS retrying at the transport layer. The
>    method guard does nothing against these; only the key does.

## Acceptance Criteria

1. **Given** `client.post(path, data: ..., idempotencyKey: 'abc-123')`
   **When** the request is sent
   **Then** the `Idempotency-Key: abc-123` header is set

2. **Given** `client.post(path, data: ..., autoIdempotencyKey: true)`
   **When** the request is sent
   **Then** an auto-generated UUID v4 is used as the key

3. **Given** `idempotencyKey` is omitted or `null` (default)
   **Then** no header is added (backward compatible)

4. **Given** `client.post(path, options: Options(headers: {'Idempotency-Key': 'manual'}), idempotencyKey: 'auto')`
   **When** both are provided
   **Then** the `idempotencyKey` parameter wins (explicit beats inherited; document this clearly)

5. **Given** a `POST` carrying an `Idempotency-Key` **and** `forceRetry()`
   **When** the response matches `retryStatusCodes`
   **Then** the request is replayed **and the same key is sent on every attempt**
   *(This is the only path on which apix itself replays a `POST`. Without
   `forceRetry()`, the method guard stops the replay and the key is never
   re-sent — see AC6.)*

6. **Given** a `POST` carrying an `Idempotency-Key` but **no** `forceRetry()`
   **When** the response matches `retryStatusCodes`
   **Then** the request is **not** replayed — the key alone must never widen
   the retry policy
   *(Regression guard: this is what makes the pair explicit rather than
   magical. See the open decision in Dev Notes.)*

7. **Given** `client.put(path, idempotencyKey: 'k')` — a method that **is**
   retried by default
   **When** the response matches `retryStatusCodes`
   **Then** the same key is sent on every attempt

8. **Supported on:** `post`, `put`, `patch`, `delete`. **Not on:** `get` (per RFC 7231, GET is already idempotent).

## Tasks / Subtasks

- [ ] Task 1: Add `idempotencyKey` parameter
  - [ ] To `ApiClient.post`, `put`, `patch`, `delete`
  - [ ] Type: `Object?` accepting `String` (literal) or `bool` (auto-gen if `true`)
  - [ ] Better DX: `String? idempotencyKey, bool autoIdempotencyKey = false` — pick one approach (lean toward `String?` + factory method `ApiClient.generateIdempotencyKey()`)

- [ ] Task 2: Header injection
  - [ ] Resolve final value (literal or generated)
  - [ ] Inject into `options.headers['Idempotency-Key']`
  - [ ] Use Dart's `dart:math.Random.secure()` + the existing `crypto` dep for UUID v4 generation (no new dep)

- [ ] Task 3: Static helper for explicit generation
  - [ ] `static String generateIdempotencyKey()` on `ApiClient` for users who want to log/persist the key before sending

- [ ] Task 4: Unit tests
  - [ ] Literal key → header set correctly
  - [ ] Auto-gen via `autoIdempotencyKey: true` → valid UUID v4 format
  - [ ] `PUT` + key → same key on every retry attempt (AC7)
  - [ ] `POST` + key + `forceRetry()` → replayed, same key each time (AC5)
  - [ ] `POST` + key **without** `forceRetry()` → exactly one attempt (AC6) —
        assert the attempt **count**, not just the header, and assert
        `retryConfig.shouldRetryMethod('POST')` is `false` so the test fails
        if the default policy is ever widened rather than silently passing
  - [ ] Conflict with `options.headers` resolved per AC4
  - [ ] No key → no header (regression)

- [ ] Task 5: Documentation
  - [ ] README section: "Idempotency for write operations"
  - [ ] **State plainly that the key does not enable retry** — pair it with
        `forceRetry()` in the example, and cross-link the method-aware retry
        section so neither reads as sufficient on its own
  - [ ] Example with Stripe-style usage

## Dev Notes

### ✅ Decided — `idempotencyKey` does NOT imply `forceRetry()`

**Settled 2026-08-06. Do not reopen mid-implementation.** The two stay
**independent**: `idempotencyKey` sets a header and nothing else; replaying a
non-idempotent request remains an explicit `forceRetry()` at the call site.

*Why:* one flag, one effect. The reason a request was replayed stays readable
where it is written. Passing a key purely for the "app killed mid-POST" case
(job 2 above) must not silently re-enable a retry policy the caller never asked
for — that would reintroduce the 2.3.0 behaviour break through a side door, and
would leave no way to express "key, but still don't retry".

*Accepted cost:* the caller must remember both, and a key alone does nothing
for apix-level retries. This is a **documentation** obligation, covered by
AC6 (regression guard) and Task 5 (the README must say plainly that the key
does not enable retry, and show the pair together).

The rejected alternative — key implies `forceRetry()` — would have required
inverting AC6 and shipping a **breaking change** entry.

### API design — recommendation

After thought, prefer two distinct fields over a polymorphic `Object?`:

```dart
Future<Response<T>> post<T>(
  String path, {
  dynamic data,
  // ...existing params
  String? idempotencyKey,
  bool autoIdempotencyKey = false,
}) {
  final key = idempotencyKey ?? (autoIdempotencyKey ? generateIdempotencyKey() : null);
  if (key != null) {
    options = (options ?? Options()).copyWith(
      headers: {...?options?.headers, 'Idempotency-Key': key},
    );
  }
  // ...
}
```

Rationale: explicit is better than polymorphic `Object?`. Avoids confusion ("does `idempotencyKey: true` mean the literal string `'true'`?").

### UUID v4 implementation (no new dep)

```dart
static String generateIdempotencyKey() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10xx
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
         '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
```

### References

- RFC 7231 §4.2.2 — Idempotent methods
- Stripe Idempotency Keys docs (canonical pattern)
- Brainstorming `[Fail #15]`
- apix 2.3.0 — `RetryConfig.retryableMethods`, `RequestOptions.forceRetry()`,
  `forceRetryKey` (`lib/src/retry/retry_interceptor.dart`,
  `lib/src/retry/retry_config.dart`)
- Working reference of the pair (key + `forceRetry`) in the example app:
  `apix_example_app/lib/core/services/retry_policy_demo_client.dart` and its
  test `apix_example_app/test/retry/retry_policy_test.dart`

## Dev Agent Record

### File List (Target)

- `lib/src/client/api_client.dart` — add params + header injection + helper
- `test/client/api_client_idempotency_test.dart` — new
- `README.md` — section on idempotency
