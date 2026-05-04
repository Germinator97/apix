import '../errors/api_exception.dart';
import 'token_provider.dart';

/// The kind of operation a [TokenProviderException] is reporting on.
enum TokenProviderOperation {
  /// A read operation on the token provider failed
  /// (`getAccessToken`, `getRefreshToken`).
  read,

  /// A write operation failed
  /// (`saveTokens` or the user-supplied `onTokenRefreshed` callback).
  write,

  /// A clear operation failed (`clearTokens`).
  clear,
}

/// Exception thrown when a [TokenProvider] operation fails.
///
/// This is raised when the underlying secure storage / keychain throws,
/// or when a custom `TokenProvider` implementation raises an exception.
/// It extends [ApiException] so existing `on ApiException catch` blocks
/// catch it transparently, while `on TokenProviderException catch` lets
/// callers distinguish credential-storage failures from network or HTTP
/// errors.
///
/// Example:
/// ```dart
/// try {
///   await client.get('/me');
/// } on TokenProviderException catch (e) {
///   if (e.operation == TokenProviderOperation.read) {
///     // keychain corrupted? prompt user to log in again
///   }
/// }
/// ```
class TokenProviderException extends ApiException {
  /// The operation that failed.
  final TokenProviderOperation operation;

  /// Creates a [TokenProviderException] with the given [operation] and
  /// [message].
  const TokenProviderException({
    required this.operation,
    required super.message,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => 'TokenProviderException(${operation.name}): $message';
}
