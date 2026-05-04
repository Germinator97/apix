# Story 12.1: Add Idempotency-Key helper for write operations

Status: ready-for-dev

## Story

As a developer,
I want a built-in `idempotencyKey` parameter on `post`/`put`/`patch`/`delete` methods,
so that retries (after app crash, network blip, or `RetryInterceptor`) don't accidentally execute the same operation twice on the backend.

## Context (why)

Stripe, Square, Mollie and most modern payment APIs require an `Idempotency-Key` header. For the internal consumer apps backends, this is critical: a double-charge or double-transfer caused by a retry is a real-money bug. Today, developers must remember to set this header manually on every write call. ApiX should make it ergonomic.

Brainstorming reference: `[Fail #15] App killed mid-POST → Idempotency keys (doc)`. We go beyond doc — we provide a helper.

## Acceptance Criteria

1. **Given** `client.post(path, data: ..., idempotencyKey: 'abc-123')`
   **When** the request is sent
   **Then** the `Idempotency-Key: abc-123` header is set

2. **Given** `client.post(path, data: ..., idempotencyKey: true)`
   **When** the request is sent
   **Then** an auto-generated UUID v4 is used as the key
   **And** the same value is preserved across retries (`RetryInterceptor` reuses `RequestOptions`)

3. **Given** `idempotencyKey` is omitted or `null` (default)
   **Then** no header is added (backward compatible)

4. **Given** `client.post(path, options: Options(headers: {'Idempotency-Key': 'manual'}), idempotencyKey: 'auto')`
   **When** both are provided
   **Then** the `idempotencyKey` parameter wins (explicit beats inherited; document this clearly)

5. **Given** retry triggers via `RetryInterceptor`
   **When** the request is replayed
   **Then** the same `Idempotency-Key` is sent (Dio already preserves headers in `RequestOptions`)

6. **Supported on:** `post`, `put`, `patch`, `delete`. **Not on:** `get` (per RFC 7231, GET is already idempotent).

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
  - [ ] Same key preserved across `RetryInterceptor` retries
  - [ ] Conflict with `options.headers` resolved per AC4
  - [ ] No key → no header (regression)

- [ ] Task 5: Documentation
  - [ ] README section: "Idempotency for write operations"
  - [ ] Example with Stripe-style usage

## Dev Notes

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

## Dev Agent Record

### File List (Target)

- `lib/src/client/api_client.dart` — add params + header injection + helper
- `test/client/api_client_idempotency_test.dart` — new
- `README.md` — section on idempotency
