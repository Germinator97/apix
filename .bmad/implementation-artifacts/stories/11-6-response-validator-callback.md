# Story 11.6: Add responseValidator callback to ApiClientConfig

Status: done

## Story

As a developer,
I want to configure a `responseValidator` callback that inspects 2xx responses and can convert them into `ApiException`,
so that legacy APIs returning `{"success": false, "error": "..."}` with HTTP 200 are caught uniformly.

## Context (why)

Some legacy backends (especially banking and telecom APIs — relevant to the internal consumer apps) return HTTP 200 even when the business operation failed, with the error encoded in the response body:

```json
{ "success": false, "error_code": "INSUFFICIENT_FUNDS", "message": "Solde insuffisant" }
```

Today the client treats this as success, returns `Response<T>` with `data` containing the error, and every consumer must remember to check `data['success']` manually. This is bug-prone (Germinator standard `[Fail #9]` from brainstorming).

## Acceptance Criteria

1. **Given** `ApiClientConfig(responseValidator: validator)`
   **When** any 2xx response is received
   **Then** `validator(response)` is invoked
   **And** if it returns an `ApiException`, that exception is thrown
   **And** if it returns `null`, the response passes through normally

2. **Given** a 4xx/5xx response
   **When** error mapping runs
   **Then** the existing `ErrorMapperInterceptor` handles it (no change)
   **And** `responseValidator` is **not** called

3. **Given** `responseValidator` is `null` (default)
   **When** any response is received
   **Then** behavior is unchanged (backward compatible)

4. **Given** `responseValidator` throws (programming error)
   **When** caught by the interceptor
   **Then** wrapped in `ApiException` with the original as `originalError`

5. **Given** the validator returns a custom subclass of `ApiException` (e.g. `BusinessException`)
   **Then** the original subclass type is preserved (catchable with `on BusinessException catch`)

## Tasks / Subtasks

- [ ] Task 1: Define typedef and add to `ApiClientConfig`
  - [ ] `typedef ResponseValidator = ApiException? Function(Response<dynamic> response);`
  - [ ] Field `responseValidator` (nullable) with `copyWith` support

- [ ] Task 2: Implement `ResponseValidatorInterceptor`
  - [ ] New file `lib/src/client/response_validator_interceptor.dart`
  - [ ] In `onResponse`, if validator configured and returns non-null exception → reject with `DioException(error: exception)`
  - [ ] The existing `_execute` in `ApiClient` will unwrap it

- [ ] Task 3: Wire into `ApiClientFactory`
  - [ ] Add to interceptor chain after `ErrorMapperInterceptor` (only fires on 2xx, so order is mainly cosmetic — place before `LoggerInterceptor` post-stage so logs see the rejection)
  - [ ] Skip if `responseValidator` is null

- [ ] Task 4: Export and document
  - [ ] Export `ResponseValidator` typedef from `lib/apix.dart`
  - [ ] README example for `{success: false}` pattern

- [ ] Task 5: Unit tests
  - [ ] Validator returns `BusinessException` → request throws `BusinessException`
  - [ ] Validator returns `null` → request returns response normally
  - [ ] Validator not configured → no overhead (regression)
  - [ ] 4xx response → validator not called (verify via spy mock)
  - [ ] Validator throws → caught and re-wrapped as `ApiException`

## Dev Notes

### Usage example

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  responseValidator: (response) {
    final body = response.data;
    if (body is Map && body['success'] == false) {
      return ApiException(
        message: body['message'] as String? ?? 'Unknown error',
        statusCode: response.statusCode,
      );
    }
    return null;
  },
);
```

### Implementation pattern

```dart
class ResponseValidatorInterceptor extends Interceptor {
  final ResponseValidator validator;

  ResponseValidatorInterceptor(this.validator);

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    try {
      final exception = validator(response);
      if (exception != null) {
        handler.reject(
          DioException(
            requestOptions: response.requestOptions,
            response: response,
            error: exception,
            type: DioExceptionType.badResponse,
          ),
        );
        return;
      }
    } catch (e, st) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: ApiException(
            message: 'responseValidator threw: $e',
            statusCode: response.statusCode,
            originalError: e,
            stackTrace: st,
          ),
          type: DioExceptionType.unknown,
        ),
      );
      return;
    }
    handler.next(response);
  }
}
```

### References

- Brainstorming `[Fail #9]` — *"200 avec erreur body → responseValidator callback"*
- `lib/src/client/api_client_factory.dart` — interceptor chain
- `lib/src/errors/error_mapper_interceptor.dart` — current 4xx/5xx handling

## Dev Agent Record

### File List (Target)

- `lib/src/client/response_validator_interceptor.dart` — new
- `lib/src/client/api_client_config.dart` — add field
- `lib/src/client/api_client_factory.dart` — wire into chain
- `lib/apix.dart` — export typedef
- `test/client/response_validator_interceptor_test.dart` — new
