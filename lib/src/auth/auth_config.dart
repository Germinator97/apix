import 'token_provider.dart';

/// Configuration for authentication handling.
///
/// Example:
/// ```dart
/// final authConfig = AuthConfig(
///   tokenProvider: MyTokenProvider(),
///   headerName: 'Authorization',
///   headerPrefix: 'Bearer',
///   refreshStatusCodes: [401],
/// );
/// ```
class AuthConfig {
  /// The token provider for managing authentication tokens.
  final TokenProvider tokenProvider;

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

  /// Creates a copy of this config with the given fields replaced.
  AuthConfig copyWith({
    TokenProvider? tokenProvider,
    String? headerName,
    String? headerPrefix,
    List<int>? refreshStatusCodes,
  }) {
    return AuthConfig(
      tokenProvider: tokenProvider ?? this.tokenProvider,
      headerName: headerName ?? this.headerName,
      headerPrefix: headerPrefix ?? this.headerPrefix,
      refreshStatusCodes: refreshStatusCodes ?? this.refreshStatusCodes,
    );
  }
}
