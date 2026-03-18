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
  const HttpException({
    required super.message,
    required int super.statusCode,
    this.responseBody,
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
    super.originalError,
    super.stackTrace,
  }) : super(statusCode: 404);

  @override
  String toString() => 'NotFoundException: $message (status: 404)';
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
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => 'ServerException: $message (status: $statusCode)';
}
