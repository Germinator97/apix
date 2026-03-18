import 'package:apix/src/auth/secure_storage_service.dart';
import 'package:apix/src/auth/token_provider.dart';

/// A ready-to-use [TokenProvider] implementation using [SecureStorageService].
///
/// This class provides secure token storage out of the box, eliminating the
/// need for developers to implement their own [TokenProvider].
///
/// Example usage:
/// ```dart
/// final tokenProvider = SecureTokenProvider();
///
/// // Use with ApiClient
/// final client = ApiClient(
///   baseUrl: 'https://api.example.com',
///   authConfig: AuthConfig(tokenProvider: tokenProvider),
/// );
///
/// // Save tokens after login
/// await tokenProvider.saveTokens(accessToken, refreshToken);
///
/// // Clear tokens on logout
/// await tokenProvider.clearTokens();
/// ```
///
/// You can also inject a custom [SecureStorageService] to share storage:
/// ```dart
/// final storage = SecureStorageService();
/// final tokenProvider = SecureTokenProvider(storage: storage);
///
/// // Use storage for other secrets
/// await storage.write('firebase_token', firebaseToken);
/// ```
///
/// Custom storage keys can be configured:
/// ```dart
/// final tokenProvider = SecureTokenProvider(
///   accessTokenKey: 'my_access_token',
///   refreshTokenKey: 'my_refresh_token',
/// );
/// ```
class SecureTokenProvider implements TokenProvider {
  final SecureStorageService _storage;

  /// The key used to store the access token.
  final String accessTokenKey;

  /// The key used to store the refresh token.
  final String refreshTokenKey;

  /// Creates a [SecureTokenProvider] with optional custom storage and keys.
  ///
  /// If no [storage] is provided, a new [SecureStorageService] is created
  /// with default secure options.
  ///
  /// Default keys are:
  /// - `accessTokenKey`: 'apix_access_token'
  /// - `refreshTokenKey`: 'apix_refresh_token'
  SecureTokenProvider({
    SecureStorageService? storage,
    this.accessTokenKey = 'apix_access_token',
    this.refreshTokenKey = 'apix_refresh_token',
  }) : _storage = storage ?? SecureStorageService();

  /// Access to the underlying [SecureStorageService] for secondary usage.
  ///
  /// This allows storing additional secrets (e.g., Firebase tokens, API keys)
  /// using the same secure storage instance.
  ///
  /// Example:
  /// ```dart
  /// await tokenProvider.storage.write('firebase_token', firebaseToken);
  /// final firebaseToken = await tokenProvider.storage.read('firebase_token');
  /// ```
  SecureStorageService get storage => _storage;

  @override
  Future<String?> getAccessToken() => _storage.read(accessTokenKey);

  @override
  Future<String?> getRefreshToken() => _storage.read(refreshTokenKey);

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(accessTokenKey, accessToken);
    await _storage.write(refreshTokenKey, refreshToken);
  }

  @override
  Future<void> clearTokens() async {
    await _storage.delete(accessTokenKey);
    await _storage.delete(refreshTokenKey);
  }
}
