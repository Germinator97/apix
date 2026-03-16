import 'package:dio/dio.dart';

import 'auth_config.dart';

/// Interceptor that automatically adds authentication headers to requests.
///
/// Uses [AuthConfig] to get the token and configure the header format.
///
/// Example:
/// ```dart
/// final authInterceptor = AuthInterceptor(authConfig);
/// dio.interceptors.add(authInterceptor);
/// ```
class AuthInterceptor extends Interceptor {
  /// The authentication configuration.
  final AuthConfig config;

  /// Creates an [AuthInterceptor] with the given [config].
  AuthInterceptor(this.config);

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
}
