import 'package:dio/dio.dart';

import 'token_provider.dart';

/// Callback for refreshing tokens (legacy approach).
///
/// Should use the refresh token to obtain new access/refresh tokens,
/// then call [TokenProvider.saveTokens] with the new values.
///
/// Returns `true` if refresh was successful, `false` otherwise.
///
/// Consider using `refreshEndpoint` with `OnTokenRefreshedCallback` instead
/// for a simpler refresh flow.
typedef RefreshCallback = Future<bool> Function(TokenProvider tokenProvider);

/// Callback invoked after successful token refresh with raw response.
///
/// The developer is responsible for parsing the response and saving tokens.
///
/// Example:
/// ```dart
/// onTokenRefreshed: (response) async {
///   final data = response.data;
///   await tokenProvider.saveTokens(
///     data['access_token'],
///     data['refresh_token'],
///   );
/// },
/// ```
typedef OnTokenRefreshedCallback = Future<void> Function(
    Response<dynamic> response);

/// Callback invoked when token refresh fails.
///
/// Called for both simplified and legacy refresh flows when the refresh
/// cannot complete (network error, invalid refresh token, server rejection, etc.).
///
/// The [error] parameter contains the reason for the failure, which can be:
/// - A [DioException] if the refresh HTTP call failed
/// - A [TypeError] or other exception if the [OnTokenRefreshedCallback] threw
/// - `null` if the refresh token was missing or the refresh returned `false`
///
/// Use this to clear stored tokens, redirect to login, or log the user out.
///
/// Example:
/// ```dart
/// onAuthFailure: (tokenProvider, error) async {
///   debugPrint('Auth failed: $error');
///   await tokenProvider.clearTokens();
///   router.go('/login');
/// },
/// ```
typedef OnAuthFailureCallback = Future<void> Function(
    TokenProvider tokenProvider, Object? error);

/// Configuration for authentication handling.
///
/// There are two approaches for token refresh:
///
/// **1. Simplified approach (recommended):** Use [refreshEndpoint] with [onTokenRefreshed]
/// ```dart
/// final authConfig = AuthConfig(
///   tokenProvider: SecureTokenProvider(),
///   refreshEndpoint: '/auth/refresh',
///   onTokenRefreshed: (response) async {
///     final data = response.data;
///     await tokenProvider.saveTokens(
///       data['access_token'],
///       data['refresh_token'],
///     );
///   },
///   onAuthFailure: (tokenProvider) async {
///     await tokenProvider.clearTokens();
///     // Navigate to login, show dialog, etc.
///   },
/// );
/// ```
///
/// **2. Legacy approach:** Use [onRefresh] callback for full control
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
  /// This is the legacy approach. Consider using [refreshEndpoint] with
  /// [onTokenRefreshed] for a simpler flow.
  ///
  /// If both [onRefresh] and [refreshEndpoint] are null, no automatic refresh
  /// will be attempted. If both are provided, [refreshEndpoint] takes priority.
  final RefreshCallback? onRefresh;

  /// Endpoint for token refresh, relative to the base URL.
  ///
  /// When provided, ApiX automatically handles the refresh HTTP call.
  /// The refresh token is sent in the request body using [refreshTokenBodyKey].
  ///
  /// Example: '/auth/refresh' or '/api/v1/token/refresh'
  final String? refreshEndpoint;

  /// Optional headers to include in the refresh request.
  ///
  /// These headers are added to the refresh request in addition to any
  /// default headers configured on the client.
  final Map<String, String>? refreshHeaders;

  /// Callback invoked with the raw [Response] after a successful refresh.
  ///
  /// The developer is responsible for parsing the response and calling
  /// [TokenProvider.saveTokens] with the new tokens.
  ///
  /// Only used when [refreshEndpoint] is provided.
  final OnTokenRefreshedCallback? onTokenRefreshed;

  /// Callback invoked when token refresh fails.
  ///
  /// Called when the refresh cannot complete, regardless of the reason:
  /// - Refresh token is null or expired
  /// - Refresh endpoint returns an error
  /// - Network error during refresh
  ///
  /// Use this to clear stored tokens and redirect the user to login.
  /// Called once per refresh attempt, even if multiple requests were queued.
  final OnAuthFailureCallback? onAuthFailure;

  /// Key name for the refresh token in the request body.
  ///
  /// Defaults to 'refresh_token'.
  final String refreshTokenBodyKey;

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
  /// Defaults to `[401]`.
  final List<int> refreshStatusCodes;

  /// Creates an [AuthConfig].
  const AuthConfig({
    required this.tokenProvider,
    this.onRefresh,
    this.refreshEndpoint,
    this.refreshHeaders,
    this.onTokenRefreshed,
    this.onAuthFailure,
    this.refreshTokenBodyKey = 'refresh_token',
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

  /// Returns true if simplified refresh flow is configured.
  bool get hasSimplifiedRefresh => refreshEndpoint != null;

  /// Creates a copy of this config with the given fields replaced.
  AuthConfig copyWith({
    TokenProvider? tokenProvider,
    RefreshCallback? onRefresh,
    String? refreshEndpoint,
    Map<String, String>? refreshHeaders,
    OnTokenRefreshedCallback? onTokenRefreshed,
    OnAuthFailureCallback? onAuthFailure,
    String? refreshTokenBodyKey,
    String? headerName,
    String? headerPrefix,
    List<int>? refreshStatusCodes,
  }) {
    return AuthConfig(
      tokenProvider: tokenProvider ?? this.tokenProvider,
      onRefresh: onRefresh ?? this.onRefresh,
      refreshEndpoint: refreshEndpoint ?? this.refreshEndpoint,
      refreshHeaders: refreshHeaders ?? this.refreshHeaders,
      onTokenRefreshed: onTokenRefreshed ?? this.onTokenRefreshed,
      onAuthFailure: onAuthFailure ?? this.onAuthFailure,
      refreshTokenBodyKey: refreshTokenBodyKey ?? this.refreshTokenBodyKey,
      headerName: headerName ?? this.headerName,
      headerPrefix: headerPrefix ?? this.headerPrefix,
      refreshStatusCodes: refreshStatusCodes ?? this.refreshStatusCodes,
    );
  }
}
