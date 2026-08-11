import 'api_exception.dart';

/// Exception for HTTP-related errors (4xx, 5xx responses).
///
/// This is the base class for all HTTP exceptions. Use this to catch
/// any HTTP error, or catch specific subtypes for granular handling.
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users');
/// } on HttpException catch (e) {
///   print('HTTP ${e.statusCode}: ${e.message}');
/// }
/// ```
class HttpException extends ApiException {
  /// The response body if available.
  final dynamic responseBody;

  /// Creates an [HttpException] with the given [message] and [statusCode].
  ///
  /// [code] carries the application-level error code read from
  /// [responseBody] — see [ApiException.code]. It is threaded through this
  /// branch of the hierarchy only: an HTTP failure is the one that comes with
  /// a body to read a code from.
  const HttpException({
    required super.message,
    required int super.statusCode,
    this.responseBody,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => 'HttpException: $message (status: $statusCode)';
}

/// Exception for client errors (4xx HTTP responses).
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users');
/// } on ClientException catch (e) {
///   print('Client error: ${e.message}');
/// }
/// ```
class ClientException extends HttpException {
  /// Creates a [ClientException] with the given [message] and [statusCode].
  const ClientException({
    required super.message,
    required super.statusCode,
    super.responseBody,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => 'ClientException: $message (status: $statusCode)';
}

/// Exception thrown when authentication is required (401 Unauthorized).
///
/// Example:
/// ```dart
/// try {
///   await client.get('/protected');
/// } on UnauthorizedException catch (e) {
///   // Redirect to login
/// }
/// ```
class UnauthorizedException extends ClientException {
  /// Creates an [UnauthorizedException] with the given [message].
  const UnauthorizedException({
    super.message = 'Unauthorized',
    super.responseBody,
    super.code,
    super.originalError,
    super.stackTrace,
  }) : super(statusCode: 401);

  @override
  String toString() => 'UnauthorizedException: $message (status: 401)';
}

/// Exception thrown when access is forbidden (403 Forbidden).
///
/// Example:
/// ```dart
/// try {
///   await client.get('/admin');
/// } on ForbiddenException catch (e) {
///   print('Access denied');
/// }
/// ```
class ForbiddenException extends ClientException {
  /// Creates a [ForbiddenException] with the given [message].
  const ForbiddenException({
    super.message = 'Forbidden',
    super.responseBody,
    super.code,
    super.originalError,
    super.stackTrace,
  }) : super(statusCode: 403);

  @override
  String toString() => 'ForbiddenException: $message (status: 403)';
}

/// Exception thrown when a resource is not found (404 Not Found).
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users/999');
/// } on NotFoundException catch (e) {
///   print('User not found');
/// }
/// ```
class NotFoundException extends ClientException {
  /// Creates a [NotFoundException] with the given [message].
  const NotFoundException({
    super.message = 'Not Found',
    super.responseBody,
    super.code,
    super.originalError,
    super.stackTrace,
  }) : super(statusCode: 404);

  @override
  String toString() => 'NotFoundException: $message (status: 404)';
}

/// Exception thrown when the client is rate limited (429 Too Many Requests).
///
/// Carries [retryAfter] when the server sent a parseable `Retry-After` header,
/// which is what lets a caller say *how long* to wait rather than showing the
/// same generic message it would show for a malformed request:
///
/// ```dart
/// on TooManyRequestsException catch (e) {
///   final wait = e.retryAfter;
///   showMessage(wait == null
///       ? 'Trop de tentatives. Réessayez plus tard.'
///       : 'Trop de tentatives. Réessayez dans ${wait.inSeconds} s.');
/// }
/// ```
///
/// Subclasses [ClientException], so existing `on ClientException` and
/// `on HttpException` clauses keep matching a 429 exactly as before.
class TooManyRequestsException extends ClientException {
  /// How long the server asked the client to wait before retrying.
  ///
  /// Null when the response carried no `Retry-After` header, or one that could
  /// not be parsed — the header is optional, so treat null as "unknown delay",
  /// never as "retry now".
  ///
  /// Independent of `RetryConfig.respectRetryAfter`: that flag decides whether
  /// the *interceptor* waits this long, not whether the server sent a value.
  /// The header is a fact about the response, so it is reported either way —
  /// which is what lets you tell the user how long to wait even when automatic
  /// retry is switched off.
  final Duration? retryAfter;

  /// Creates a [TooManyRequestsException].
  const TooManyRequestsException({
    super.message = 'Too Many Requests',
    this.retryAfter,
    super.responseBody,
    super.code,
    super.originalError,
    super.stackTrace,
  }) : super(statusCode: 429);

  @override
  String toString() {
    final buffer = StringBuffer('TooManyRequestsException: $message');
    buffer.write(' (status: 429');
    if (retryAfter != null) {
      buffer.write(', retry after: ${retryAfter!.inSeconds}s');
    }
    buffer.write(')');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TooManyRequestsException &&
          super == other &&
          retryAfter == other.retryAfter;

  @override
  int get hashCode => super.hashCode ^ retryAfter.hashCode;
}

/// Exception for server errors (5xx HTTP responses).
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users');
/// } on ServerException catch (e) {
///   print('Server error: ${e.message}');
/// }
/// ```
class ServerException extends HttpException {
  /// Creates a [ServerException] with the given [message] and [statusCode].
  const ServerException({
    required super.message,
    required super.statusCode,
    super.responseBody,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => 'ServerException: $message (status: $statusCode)';
}
