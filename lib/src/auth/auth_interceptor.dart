import 'package:dio/dio.dart';

import 'auth_config.dart';

/// Interceptor that automatically adds authentication headers to requests
/// and handles token refresh on configured status codes.
///
/// Uses [AuthConfig] to get the token, configure the header format,
/// and handle token refresh.
///
/// Example:
/// ```dart
/// final authInterceptor = AuthInterceptor(authConfig, dio);
/// dio.interceptors.add(authInterceptor);
/// ```
class AuthInterceptor extends Interceptor {
  /// The authentication configuration.
  final AuthConfig config;

  /// The Dio instance for retrying requests after refresh.
  final Dio dio;

  /// Creates an [AuthInterceptor] with the given [config] and [dio].
  AuthInterceptor(this.config, this.dio);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await config.tokenProvider.getAccessToken();

    if (token != null) {
      options.headers[config.headerName] = config.formatHeaderValue(token);
    }

    handler.next(options);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;

    // Check if we should refresh
    if (statusCode != null &&
        config.shouldRefresh(statusCode) &&
        config.onRefresh != null) {
      // Attempt refresh
      final refreshSuccess = await config.onRefresh!(config.tokenProvider);

      if (refreshSuccess) {
        // Retry the original request with new token
        try {
          final response = await _retryRequest(err.requestOptions);
          handler.resolve(response);
          return;
        } on DioException catch (e) {
          handler.next(e);
          return;
        }
      }
    }

    handler.next(err);
  }

  /// Retries a request with fresh token.
  Future<Response<dynamic>> _retryRequest(RequestOptions requestOptions) async {
    final token = await config.tokenProvider.getAccessToken();

    if (token != null) {
      requestOptions.headers[config.headerName] =
          config.formatHeaderValue(token);
    }

    return dio.fetch(requestOptions);
  }
}
