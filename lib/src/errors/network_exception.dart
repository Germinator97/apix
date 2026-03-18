import 'api_exception.dart';

/// Exception for network-related errors (connectivity, timeout).
///
/// This is the base class for all network exceptions. Use this to catch
/// any network-related error, or catch specific subtypes for granular handling.
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users');
/// } on NetworkException catch (e) {
///   print('Network error: ${e.message}');
/// }
/// ```
class NetworkException extends ApiException {
  /// Creates a [NetworkException] with the given [message].
  const NetworkException({
    required super.message,
    super.statusCode,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => 'NetworkException: $message';
}

/// Exception thrown when a request times out.
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users');
/// } on TimeoutException catch (e) {
///   print('Request timed out after ${e.duration}');
/// }
/// ```
class TimeoutException extends NetworkException {
  /// The duration after which the timeout occurred.
  final Duration? duration;

  /// Creates a [TimeoutException] with the given [message].
  const TimeoutException({
    required super.message,
    this.duration,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('TimeoutException: $message');
    if (duration != null) {
      buffer.write(' (after ${duration!.inMilliseconds}ms)');
    }
    return buffer.toString();
  }
}

/// Exception thrown when a connection cannot be established.
///
/// This typically occurs when:
/// - No internet connection
/// - Server is unreachable
/// - DNS resolution fails
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users');
/// } on ConnectionException catch (e) {
///   print('Cannot connect: ${e.message}');
/// }
/// ```
class ConnectionException extends NetworkException {
  /// Creates a [ConnectionException] with the given [message].
  const ConnectionException({
    required super.message,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => 'ConnectionException: $message';
}
