# Story 11.5: Add UnexpectedContentTypeException with optional check

Status: done

## Story

As a developer,
I want a way to detect responses where the `Content-Type` doesn't match what `*AndDecode` expects (e.g. an HTML 200 from a captive Wi-Fi portal),
so that I get a clear typed exception instead of a confusing `FormatException` or silent corrupted data.

## Context (why)

Captive portals (hotel Wi-Fi, public networks) often intercept HTTPS requests and return a 200 OK with an HTML login page. Without a `Content-Type` check, `getAndDecode<User>` will try to parse the HTML as JSON and throw `FormatException`. With the new `ParsingException` (story 11.1), it becomes `ParsingException` — better, but still ambiguous: did the backend send invalid JSON, or did a network middlebox intercept?

A dedicated check + exception lets developers handle the captive-portal case explicitly (e.g. show a "check your network" UI).

## Acceptance Criteria

1. **Given** `ApiClientConfig(strictContentType: true)` (opt-in)
   **When** an `*AndDecode` method receives a response whose `Content-Type` does not start with `application/json`
   **Then** `UnexpectedContentTypeException` is thrown
   **And** parsing is **not** attempted

2. **Given** `UnexpectedContentTypeException`
   **Then** it extends `ApiException`
   **And** has `expectedContentType` and `actualContentType` fields
   **And** `statusCode` is set from the response

3. **Given** `ApiClientConfig(strictContentType: false)` (default)
   **When** an `*AndDecode` method receives any response
   **Then** behavior is unchanged (backward compatible — no perf cost)

4. **Given** a response with `Content-Type: application/json; charset=utf-8`
   **When** strict mode is on
   **Then** the check passes (matches `application/json` prefix, ignores charset)

5. **Given** a response with no `Content-Type` header
   **When** strict mode is on
   **Then** `UnexpectedContentTypeException(actualContentType: null)` is thrown

6. **Given** `*AndParse` (untyped parser)
   **Then** the check is **not** applied (the parser handles arbitrary types by design)

## Tasks / Subtasks

- [ ] Task 1: Create `UnexpectedContentTypeException`
  - [ ] New file `lib/src/errors/unexpected_content_type_exception.dart`
  - [ ] Extends `ApiException`
  - [ ] Fields: `expectedContentType` (String), `actualContentType` (String?)

- [ ] Task 2: Add `strictContentType` to `ApiClientConfig`
  - [ ] Default `false`
  - [ ] Update `copyWith`

- [ ] Task 3: Apply check in `*AndDecode` methods
  - [ ] Helper `_assertJsonContentType(response)` in `ApiClient`
  - [ ] Called from all `getAndDecode`, `postAndDecode`, `putAndDecode`, `patchAndDecode` and their `*Data` variants
  - [ ] Skip in `*AndParse` (untyped)
  - [ ] Skip if response is `204 No Content` (already handled by `_requireData`)

- [ ] Task 4: Export and document
  - [ ] Add to `lib/apix.dart`
  - [ ] README section: "Detecting captive portals / wrong Content-Type"

- [ ] Task 5: Unit tests
  - [ ] HTML response with strict mode → `UnexpectedContentTypeException`
  - [ ] JSON response with strict mode → passes
  - [ ] JSON with charset → passes
  - [ ] Missing Content-Type with strict mode → exception
  - [ ] Strict mode off → no check (regression for performance/backward compat)
  - [ ] `*AndParse` is unaffected

## Dev Notes

### Implementation pattern

```dart
// lib/src/errors/unexpected_content_type_exception.dart
class UnexpectedContentTypeException extends ApiException {
  final String expectedContentType;
  final String? actualContentType;

  const UnexpectedContentTypeException({
    required this.expectedContentType,
    required this.actualContentType,
    required super.statusCode,
    super.message = 'Unexpected Content-Type',
  });

  @override
  String toString() =>
      'UnexpectedContentTypeException: expected $expectedContentType, '
      'got ${actualContentType ?? "(none)"} (status: $statusCode)';
}

// In api_client.dart
void _assertJsonContentType(Response<dynamic> response) {
  if (!config.strictContentType) return;
  final raw = response.headers.value('content-type');
  if (raw == null || !raw.toLowerCase().startsWith('application/json')) {
    throw UnexpectedContentTypeException(
      expectedContentType: 'application/json',
      actualContentType: raw,
      statusCode: response.statusCode,
    );
  }
}
```

### Why opt-in

Some APIs return `text/plain` for valid JSON, or omit `Content-Type`. Forcing strict mode by default would break existing integrations. Opt-in keeps backward compat and lets developers tighten security in fintech contexts.

### References

- `lib/src/client/api_client.dart` — `*AndDecode` methods
- `lib/src/client/api_client_config.dart`

## Dev Agent Record

### File List (Target)

- `lib/src/errors/unexpected_content_type_exception.dart` — new
- `lib/src/client/api_client_config.dart` — add `strictContentType`
- `lib/src/client/api_client.dart` — add `_assertJsonContentType` + call in `*AndDecode`
- `lib/apix.dart` — export
- `test/errors/unexpected_content_type_exception_test.dart` — new
- `test/client/api_client_content_type_test.dart` — new
