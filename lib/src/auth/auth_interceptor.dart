import 'dart:async';

import 'package:dio/dio.dart';

import '../errors/http_exception.dart';
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
  /// Key used in [RequestOptions.extra] to mark refresh requests.
  ///
  /// Refresh requests skip auth header injection and refresh-on-error logic
  /// to prevent recursive refresh loops and deadlocks.
  static const String isRefreshRequestKey = 'apix_is_refresh_request';

  /// Key used in [RequestOptions.extra] to mark auth-retried requests.
  ///
  /// Prevents infinite loop: if the retried request gets 401 again,
  /// the interceptor will not attempt another refresh.
  static const String isAuthRetryKey = 'apix_is_auth_retry';

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
    try {
      // Skip auth header for refresh requests to avoid injecting the expired token
      if (options.extra[isRefreshRequestKey] == true) {
        handler.next(options);
        return;
      }

      final token = await config.tokenProvider.getAccessToken();

      if (token != null && token.isNotEmpty) {
        options.headers[config.headerName] = config.formatHeaderValue(token);
      }

      handler.next(options);
    } catch (e) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: e,
          type: DioExceptionType.unknown,
        ),
      );
    }
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      // Never attempt refresh for refresh requests themselves (prevents deadlock)
      // or auth-retried requests (prevents infinite loop)
      if (err.requestOptions.extra[isRefreshRequestKey] == true ||
          err.requestOptions.extra[isAuthRetryKey] == true) {
        handler.next(err);
        return;
      }

      final statusCode = err.response?.statusCode;

      // Check if we should refresh (simplified or legacy approach)
      final canRefresh =
          config.hasSimplifiedRefresh || config.onRefresh != null;
      if (statusCode != null &&
          config.shouldRefresh(statusCode) &&
          canRefresh) {
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
              message: 'Token refresh failed',
              error: const AuthException('Token refresh failed'),
              type: DioExceptionType.unknown,
            ),
          );
          return;
        }
      }

      handler.next(err);
    } catch (e) {
      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error: e,
          type: DioExceptionType.unknown,
        ),
      );
    }
  }

  /// Handles token refresh with queue coordination.
  ///
  /// If a refresh is already in progress, waits for it to complete.
  /// Otherwise, initiates a new refresh and notifies all waiting requests.
  ///
  /// Supports two approaches:
  /// 1. **Simplified flow:** Uses [AuthConfig.refreshEndpoint] to make the
  ///    refresh call automatically, then invokes [AuthConfig.onTokenRefreshed].
  /// 2. **Legacy flow:** Delegates to [AuthConfig.onRefresh] callback.
  ///
  /// The simplified flow takes priority if [AuthConfig.refreshEndpoint] is set.
  Future<bool> _handleRefresh() async {
    // If refresh is already in progress, wait for it
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    // Start a new refresh
    _refreshCompleter = Completer<bool>();

    try {
      bool success;

      // Simplified refresh flow (priority)
      if (config.hasSimplifiedRefresh) {
        success = await _performSimplifiedRefresh();
      }
      // Legacy refresh flow
      else if (config.onRefresh != null) {
        success = await config.onRefresh!(config.tokenProvider);
      } else {
        success = false;
      }

      // Notify once on failure (before completing, so queued requests
      // haven't reacted yet)
      if (!success) {
        await _notifyAuthFailure(null);
      }

      _refreshCompleter!.complete(success);
      return success;
    } catch (e) {
      await _notifyAuthFailure(e);
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// Performs the simplified refresh flow using [AuthConfig.refreshEndpoint].
  ///
  /// Makes a POST request to the refresh endpoint with the refresh token,
  /// then invokes [AuthConfig.onTokenRefreshed] with the response.
  /// Lets exceptions propagate to [_handleRefresh] for error reporting.
  Future<bool> _performSimplifiedRefresh() async {
    final refreshToken = await config.tokenProvider.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    final response = await dio.post<dynamic>(
      config.refreshEndpoint!,
      data: {config.refreshTokenBodyKey: refreshToken},
      options: Options(
        headers: config.refreshHeaders,
        extra: {isRefreshRequestKey: true},
      ),
    );

    if (config.onTokenRefreshed != null) {
      await config.onTokenRefreshed!(response);
    }

    return true;
  }

  /// Notifies the developer that auth has failed.
  ///
  /// Called exactly once per refresh attempt, even when multiple
  /// requests are queued behind the same refresh.
  /// [error] contains the failure reason, or `null` if the refresh
  /// returned `false` without throwing.
  Future<void> _notifyAuthFailure(Object? error) async {
    if (config.onAuthFailure != null) {
      try {
        await config.onAuthFailure!(config.tokenProvider, error);
      } catch (_) {
        // Don't let callback errors disrupt the interceptor flow
      }
    }
  }

  /// Retries a request with fresh token.
  ///
  /// Marks the request with [isAuthRetryKey] so that if it fails again
  /// with a refresh-triggering status code, no further refresh is attempted.
  Future<Response<dynamic>> _retryRequest(RequestOptions requestOptions) async {
    final token = await config.tokenProvider.getAccessToken();

    if (token != null) {
      requestOptions.headers[config.headerName] =
          config.formatHeaderValue(token);
    }

    requestOptions.extra[isAuthRetryKey] = true;
    return dio.fetch(requestOptions);
  }
}

/// Exception thrown when token refresh fails.
///
/// Extends [UnauthorizedException] so it can be caught with
/// `on UnauthorizedException catch` alongside normal 401 errors.
class AuthException extends UnauthorizedException {
  /// Creates an [AuthException] with the given [message].
  const AuthException(String message) : super(message: message);

  @override
  String toString() => 'AuthException: $message';
}
