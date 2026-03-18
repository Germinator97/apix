/// Interface for providing authentication tokens.
///
/// Implement this interface to integrate your token storage with apix.
/// All methods are async for compatibility with secure storage solutions.
///
/// Example:
/// ```dart
/// class MyTokenProvider implements TokenProvider {
///   final FlutterSecureStorage _storage;
///
///   MyTokenProvider(this._storage);
///
///   @override
///   Future<String?> getAccessToken() => _storage.read(key: 'access_token');
///
///   @override
///   Future<String?> getRefreshToken() => _storage.read(key: 'refresh_token');
///
///   @override
///   Future<void> saveTokens(String accessToken, String refreshToken) async {
///     await _storage.write(key: 'access_token', value: accessToken);
///     await _storage.write(key: 'refresh_token', value: refreshToken);
///   }
///
///   @override
///   Future<void> clearTokens() async {
///     await _storage.delete(key: 'access_token');
///     await _storage.delete(key: 'refresh_token');
///   }
/// }
/// ```
abstract class TokenProvider {
  /// Returns the current access token, or null if not available.
  Future<String?> getAccessToken();

  /// Returns the current refresh token, or null if not available.
  Future<String?> getRefreshToken();

  /// Saves both tokens after a successful authentication or refresh.
  Future<void> saveTokens(String accessToken, String refreshToken);

  /// Clears all tokens (e.g., on logout).
  Future<void> clearTokens();
}
