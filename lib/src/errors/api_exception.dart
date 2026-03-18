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

  /// The original error that caused this exception.
  final Object? originalError;

  /// The stack trace from the original error.
  final StackTrace? stackTrace;

  /// Creates an [ApiException] with the given [message].
  ///
  /// Optionally provide [statusCode] for HTTP errors and [originalError]
  /// for the underlying cause.
  const ApiException({
    required this.message,
    this.statusCode,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('ApiException: $message');
    if (statusCode != null) {
      buffer.write(' (status: $statusCode)');
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiException &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          statusCode == other.statusCode;

  @override
  int get hashCode => message.hashCode ^ statusCode.hashCode;
}
