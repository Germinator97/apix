import '../errors/api_exception.dart';
import 'token_provider.dart';

/// The kind of operation a [TokenProviderException] is reporting on.
///
/// ## Which of these apix itself produces
///
/// Only [read] and [write]. That distinction is documented per value below,
/// and pinned by a test, because it decides whether a `switch` on
/// `e.operation` has a branch that can never be taken — and a branch that
/// never runs looks exactly like a branch whose case never happens.
enum TokenProviderOperation {
  /// A read failed — `getAccessToken` or `getRefreshToken`.
  ///
  /// **Produced by apix**, on three paths: injecting the header in
  /// `onRequest`, reading the refresh token before a refresh call, and reading
  /// the new access token after a successful one.
  read,

  /// A write failed — `saveTokens`, or the `onTokenRefreshed` callback that is
  /// supposed to call it.
  ///
  /// **Produced by apix**, when persisting the tokens a refresh just obtained.
  write,

  /// A clear failed — `clearTokens`.
  ///
  /// **Never produced by apix**, and that is by design rather than by
  /// omission: apix does not own your logout. `clearTokens` is called from
  /// your own code — typically inside `AuthConfig.onAuthFailure` — so a
  /// failure there is raised in your frame, where you can already see it.
  ///
  /// The value exists for **you** to raise from a custom [TokenProvider], so a
  /// caller of your provider can tell a failed wipe from a failed read. Do not
  /// expect apix to hand you one: a `case TokenProviderOperation.clear` in a
  /// `catch` around an apix call is a branch that will never be taken.
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
