# Story 11.1: Implement ParsingException for *AndDecode/*AndParse

Status: done

## Story

As a developer,
I want `*AndDecode` and `*AndParse` methods to throw `ParsingException` (extending `ApiException`) when parsing fails,
so that `on ApiException catch` reliably catches all client-side errors as promised by the 2.0.0 contract.

## Context (why)

The 2.0.0 release advertised: *"`ApiClient` methods now throw typed `ApiException` directly"*. However, when `fromJson()` or a custom `parser()` throws (e.g. `FormatException` on truncated JSON, `TypeError` on shape mismatch), the exception bubbles up unmapped. Callers using `on ApiException catch` miss it — contract violation.

## Acceptance Criteria

1. **Given** an `*AndDecode` call (e.g. `getAndDecode`)
   **When** the response body is not a valid JSON object that `fromJson` can consume
   **Then** `ParsingException` is thrown (a subtype of `ApiException`)
   **And** `originalError` and `stackTrace` are preserved

2. **Given** an `*AndParse` call (e.g. `getAndParse`)
   **When** the user-provided `parser` callback throws
   **Then** `ParsingException` is thrown with the same preservation

3. **Given** the envelope variants (`*AndDecodeData`, `*AndParseData`, list variants)
   **When** parsing fails at any level (envelope unwrap or item parse)
   **Then** `ParsingException` is thrown

4. **Given** `ParsingException`
   **Then** it extends `ApiException`
   **And** `statusCode` is set from the underlying HTTP response when available
   **And** `message` is human-readable: `"Failed to parse response body: <cause>"`

5. **Given** existing callers using `on ApiException catch`
   **When** parsing fails
   **Then** they catch the new exception transparently (no migration needed)

## Tasks / Subtasks

- [ ] Task 1: Create `ParsingException` class
  - [ ] New file `lib/src/errors/parsing_exception.dart`
  - [ ] Extends `ApiException`
  - [ ] Constructor takes `message`, optional `statusCode`, `originalError`, `stackTrace`

- [ ] Task 2: Wrap parsing calls in `ApiClient`
  - [ ] `getAndDecode`, `postAndDecode`, `putAndDecode`, `patchAndDecode` (`api_client.dart:232,283,325,367`)
  - [ ] `getAndParse`, `postAndParse`, `putAndParse`, `patchAndParse` (`api_client.dart:208,253,304,346`)
  - [ ] All `*Data` variants (envelope unwrap and list)
  - [ ] Wrap user callbacks (`fromJson`, `parser`) in try/catch → `ParsingException`
  - [ ] Wrap `_extractData` and list casts (`as List<dynamic>`) too

- [ ] Task 3: Export and document
  - [ ] Add export in `lib/apix.dart`
  - [ ] Update README error hierarchy section

- [ ] Task 4: Unit tests
  - [ ] `test/errors/parsing_exception_test.dart` — class shape, hierarchy
  - [ ] `test/client/api_client_parsing_test.dart` — invalid JSON, wrong type cast, parser throws, envelope shape mismatch
  - [ ] Verify `on ApiException catch` catches `ParsingException`

## Dev Notes

### Implementation pattern

```dart
// lib/src/errors/parsing_exception.dart
class ParsingException extends ApiException {
  const ParsingException({
    required super.message,
    super.statusCode,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('ParsingException: $message');
    if (statusCode != null) buffer.write(' (status: $statusCode)');
    return buffer.toString();
  }
}

// Helper in api_client.dart
T _decode<T>(
  Response<dynamic> response,
  T Function() decode,
) {
  try {
    return decode();
  } catch (e, st) {
    throw ParsingException(
      message: 'Failed to parse response body: $e',
      statusCode: response.statusCode,
      originalError: e,
      stackTrace: st,
    );
  }
}
```

Then each `*AndDecode`/`*AndParse` calls `_decode(response, () => fromJson(_requireData(response)))`.

### References

- CHANGELOG 2.0.0 — *"`ApiClient` methods now throw typed `ApiException` directly"*
- `lib/src/client/api_client.dart:232` (current `fromJson` call without try/catch)

## Dev Agent Record

### File List (Target)

- `lib/src/errors/parsing_exception.dart` — new
- `lib/src/client/api_client.dart` — wrap parsing calls
- `lib/apix.dart` — export
- `test/errors/parsing_exception_test.dart` — new
- `test/client/api_client_parsing_test.dart` — new
