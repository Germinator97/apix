import 'dart:async';

import 'package:dio/dio.dart';

import '../errors/api_exception.dart';
import 'auth_config.dart';

/// Interceptor that automatically adds authentication headers to requests
/// and handles token refresh on configured status codes.
///
/// Uses [AuthConfig] to get the token, configure the header format,
/// and handle token refresh. Implements a queue pattern using [Completer]
/// to handle concurrent requests during token refresh.
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

  /// Completer for coordinating concurrent refresh requests.
  /// When not null, a refresh is in progress and other requests should wait.
  Completer<bool>? _refreshCompleter;

  /// Creates an [AuthInterceptor] with the given [config] and [dio].
  AuthInterceptor(this.config, this.dio);

  /// Whether a refresh is currently in progress.
  bool get isRefreshing => _refreshCompleter != null;

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
      // Wait for refresh and retry
      final refreshSuccess = await _handleRefresh();

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
      } else {
        // Refresh failed - reject with AuthException
        handler.reject(
          DioException(
            requestOptions: err.requestOptions,
            error: const AuthException('Token refresh failed'),
            type: DioExceptionType.unknown,
          ),
        );
        return;
      }
    }

    handler.next(err);
  }

  /// Handles token refresh with queue coordination.
  ///
  /// If a refresh is already in progress, waits for it to complete.
  /// Otherwise, initiates a new refresh and notifies all waiting requests.
  Future<bool> _handleRefresh() async {
    // If refresh is already in progress, wait for it
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    // Start a new refresh
    _refreshCompleter = Completer<bool>();

    try {
      final success = await config.onRefresh!(config.tokenProvider);
      _refreshCompleter!.complete(success);
      return success;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
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

/// Exception thrown when authentication fails.
class AuthException extends ApiException {
  /// Creates an [AuthException] with the given [message].
  const AuthException(String message) : super(message: message);

  @override
  String toString() => 'AuthException: $message';
}
