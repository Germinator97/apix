/// Base exception class for all API-related errors.
///
/// All exceptions thrown by apix extend this class, allowing developers
/// to catch all API errors with a single type or handle specific subtypes.
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users');
/// } on ApiException catch (e) {
///   print('API error: ${e.message}');
/// }
/// ```
class ApiException implements Exception {
  /// Human-readable error message.
  final String message;

  /// HTTP status code if available.
  final int? statusCode;

  /// Application-level error code read from the response body, if the backend
  /// sent one.
  ///
  /// Branch on this rather than on [statusCode] whenever the backend publishes
  /// a stable code: the same business case can drift from `400` to `409` to
  /// `422` across server revisions without changing meaning, and a call site
  /// keyed on the status silently changes behaviour when it does. Keep status
  /// branching for the cross-cutting categories — `401` refresh, `403`, a
  /// generic `5xx` — or when no code is guaranteed.
  ///
  /// ```dart
  /// on ApiException catch (e) {
  ///   switch (e.code) {
  ///     case 'OPERATION_NOT_RETRYABLE': // ...
  ///     case 'FILE_STORAGE_UNAVAILABLE': // ...
  ///   }
  /// }
  /// ```
  ///
  /// Always a `String`, even when the backend sends a number: a JSON `4001`
  /// arrives here as `'4001'`, so a `switch` never has to care which of the two
  /// the server picked. Null when the body carried no code, was not a JSON
  /// object, or the value was neither a string nor a number — and null on every
  /// non-HTTP failure (timeout, connection loss), which has no body to read.
  ///
  /// Which key is read is configurable through `ApiClientConfig.errorCodeKey`.
  final String? code;

  /// The original error that caused this exception.
  final Object? originalError;

  /// The stack trace from the original error.
  final StackTrace? stackTrace;

  /// Creates an [ApiException] with the given [message].
  ///
  /// Optionally provide [statusCode] for HTTP errors, [code] for the
  /// application-level error code, and [originalError] for the underlying
  /// cause.
  const ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('ApiException: $message');
    if (statusCode != null) {
      buffer.write(' (status: $statusCode)');
    }
    if (code != null) {
      buffer.write(' [code: $code]');
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiException &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          statusCode == other.statusCode &&
          code == other.code;

  @override
  int get hashCode => message.hashCode ^ statusCode.hashCode ^ code.hashCode;
}
