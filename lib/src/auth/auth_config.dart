import 'token_provider.dart';

/// Callback for refreshing tokens.
///
/// Should use the refresh token to obtain new access/refresh tokens,
/// then call [TokenProvider.saveTokens] with the new values.
///
/// Returns `true` if refresh was successful, `false` otherwise.
typedef RefreshCallback = Future<bool> Function(TokenProvider tokenProvider);

/// Configuration for authentication handling.
///
/// Example:
/// ```dart
/// final authConfig = AuthConfig(
///   tokenProvider: MyTokenProvider(),
///   onRefresh: (provider) async {
///     final refreshToken = await provider.getRefreshToken();
///     if (refreshToken == null) return false;
///
///     final response = await dio.post('/auth/refresh', data: {
///       'refresh_token': refreshToken,
///     });
///
///     await provider.saveTokens(
///       response.data['access_token'],
///       response.data['refresh_token'],
///     );
///     return true;
///   },
/// );
/// ```
class AuthConfig {
  /// The token provider for managing authentication tokens.
  final TokenProvider tokenProvider;

  /// Callback to refresh tokens when a refresh-triggering status code is received.
  ///
  /// If null, no automatic refresh will be attempted.
  final RefreshCallback? onRefresh;

  /// The header name for the authorization token.
  ///
  /// Defaults to 'Authorization'.
  final String headerName;

  /// The prefix for the token value in the header.
  ///
  /// Defaults to 'Bearer'. Set to empty string for no prefix.
  final String headerPrefix;

  /// HTTP status codes that trigger a token refresh.
  ///
  /// Defaults to [401].
  final List<int> refreshStatusCodes;

  /// Creates an [AuthConfig].
  const AuthConfig({
    required this.tokenProvider,
    this.onRefresh,
    this.headerName = 'Authorization',
    this.headerPrefix = 'Bearer',
    this.refreshStatusCodes = const [401],
  });

  /// Formats the authorization header value.
  String formatHeaderValue(String token) {
    if (headerPrefix.isEmpty) {
      return token;
    }
    return '$headerPrefix $token';
  }

  /// Returns true if the given status code should trigger a token refresh.
  bool shouldRefresh(int statusCode) {
    return refreshStatusCodes.contains(statusCode);
  }

  /// Creates a copy of this config with the given fields replaced.
  AuthConfig copyWith({
    TokenProvider? tokenProvider,
    RefreshCallback? onRefresh,
    String? headerName,
    String? headerPrefix,
    List<int>? refreshStatusCodes,
  }) {
    return AuthConfig(
      tokenProvider: tokenProvider ?? this.tokenProvider,
      onRefresh: onRefresh ?? this.onRefresh,
      headerName: headerName ?? this.headerName,
      headerPrefix: headerPrefix ?? this.headerPrefix,
      refreshStatusCodes: refreshStatusCodes ?? this.refreshStatusCodes,
    );
  }
}
