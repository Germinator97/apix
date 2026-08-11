import 'dart:async';

import 'package:dio/dio.dart';

import '../errors/api_exception.dart';
import '../errors/error_mapper_interceptor.dart';
import '../errors/http_exception.dart';
import '../errors/network_exception.dart';
import 'auth_config.dart';
import 'token_provider.dart';
import 'token_provider_exception.dart';

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
  Completer<_RefreshOutcome>? _refreshCompleter;

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

      String? token;
      try {
        token = await config.tokenProvider.getAccessToken();
      } catch (e, st) {
        handler.reject(
          DioException(
            requestOptions: options,
            error: TokenProviderException(
              operation: TokenProviderOperation.read,
              message: 'Token retrieval failed: $e',
              originalError: e,
              stackTrace: st,
            ),
            type: DioExceptionType.unknown,
          ),
        );
        return;
      }

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
        final outcome = await _handleRefresh();

        switch (outcome) {
          case _RefreshSuccess():
            // Retry the original request with new token
            try {
              final response = await _retryRequest(err.requestOptions);
              handler.resolve(response);
              return;
            } on DioException catch (e) {
              handler.next(e);
              return;
            }
          case _RefreshNetworkFailure(exception: final networkException):
            // Refresh hit a network error — propagate as-is, do NOT log the
            // user out. onAuthFailure was already skipped in _handleRefresh.
            handler.reject(
              DioException(
                requestOptions: err.requestOptions,
                message: networkException.message,
                error: networkException,
                type: DioExceptionType.unknown,
              ),
            );
            return;
          case _RefreshAuthFailure(error: final cause):
            // Surface a typed TokenProviderException directly when present;
            // otherwise fall back to AuthException (preserves the 1.x/2.x
            // contract for opaque refresh failures while keeping the cause
            // accessible via originalError).
            final ApiException finalError = cause is TokenProviderException
                ? cause
                : AuthException(
                    'Token refresh failed',
                    originalError: cause,
                  );
            handler.reject(
              DioException(
                requestOptions: err.requestOptions,
                message: finalError.message,
                error: finalError,
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
  ///
  /// Returns a [_RefreshOutcome] that distinguishes:
  /// - success,
  /// - a network failure (e.g. offline) where we must NOT log the user out,
  /// - an auth failure where the session is genuinely broken.
  Future<_RefreshOutcome> _handleRefresh() async {
    // If refresh is already in progress, wait for it
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    // Start a new refresh
    _refreshCompleter = Completer<_RefreshOutcome>();

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

      if (success) {
        const outcome = _RefreshSuccess();
        _refreshCompleter!.complete(outcome);
        return outcome;
      }

      // Notify once on failure (before completing, so queued requests
      // haven't reacted yet)
      await _notifyAuthFailure(null);
      const outcome = _RefreshAuthFailure(null);
      _refreshCompleter!.complete(outcome);
      return outcome;
    } catch (e) {
      // Distinguish network errors from auth errors so the caller can react
      // appropriately.
      final networkException = _classifyAsNetwork(e);
      if (networkException != null) {
        // Network failure: do NOT call onAuthFailure (not a credential issue).
        final outcome = _RefreshNetworkFailure(networkException);
        _refreshCompleter!.complete(outcome);
        return outcome;
      }

      await _notifyAuthFailure(e);
      final outcome = _RefreshAuthFailure(e);
      _refreshCompleter!.complete(outcome);
      return outcome;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// Returns a [NetworkException] when [error] represents a transport-level
  /// failure (offline, DNS, timeout, …), or `null` otherwise. Used to keep
  /// network blips from masquerading as auth failures.
  NetworkException? _classifyAsNetwork(Object error) {
    if (error is NetworkException) return error;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          final mapped = ErrorMapperInterceptor.mapDioException(error);
          return mapped is NetworkException ? mapped : null;
        // badCertificate, badResponse, cancel, unknown, `transformTimeout` (a
        // data-transformation timeout added in dio 5.10.0) and any future types
        // are not transport blips, so they are not network failures. Named
        // cases are intentionally omitted so this default stays reachable on
        // older dio (apix supports dio >=5.4.0, where new values can't be named
        // without breaking the lower bound).
        default:
          return null;
      }
    }
    return null;
  }

  /// Performs the simplified refresh flow using [AuthConfig.refreshEndpoint].
  ///
  /// Makes a POST request to the refresh endpoint with the refresh token,
  /// then invokes [AuthConfig.onTokenRefreshed] with the response.
  /// Lets exceptions propagate to [_handleRefresh] for error reporting.
  /// Errors from the [TokenProvider] are re-thrown as
  /// [TokenProviderException] so callers can distinguish them from HTTP
  /// failures.
  Future<bool> _performSimplifiedRefresh() async {
    String? refreshToken;
    try {
      refreshToken = await config.tokenProvider.getRefreshToken();
    } catch (e, st) {
      throw TokenProviderException(
        operation: TokenProviderOperation.read,
        message: 'Refresh token retrieval failed: $e',
        originalError: e,
        stackTrace: st,
      );
    }
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
      try {
        await config.onTokenRefreshed!(response);
      } catch (e, st) {
        throw TokenProviderException(
          operation: TokenProviderOperation.write,
          message: 'Token persistence failed in onTokenRefreshed: $e',
          originalError: e,
          stackTrace: st,
        );
      }
    }

    return true;
  }

  /// Notifies the developer that auth has failed.
  ///
  /// Called exactly once per refresh attempt, even when multiple
  /// requests are queued behind the same refresh.
  /// [error] contains the failure reason, or `null` if the refresh
  /// returned `false` without throwing.
  /// Notifies the consumer that the session is genuinely broken.
  ///
  /// Failures of the callback are swallowed, and that is load-bearing rather
  /// than lazy: this runs *before* `_refreshCompleter.complete(...)`, so a
  /// throwing `onAuthFailure` would leave every queued request waiting on a
  /// completer that is never completed — a deadlock, not a lost notification.
  ///
  /// Same contract as every other consumer callback (see `guardObserver`), and
  /// the same reason for not reporting the failure anywhere: there is no
  /// channel left that is known to work.
  Future<void> _notifyAuthFailure(Object? error) async {
    if (config.onAuthFailure != null) {
      try {
        await config.onAuthFailure!(config.tokenProvider, error);
      } catch (_) {
        // Swallowing here keeps the refresh queue from deadlocking.
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
  ///
  /// When the failure has an underlying cause (the exception that caused
  /// `_handleRefresh` to abort), pass it as [originalError] so callers can
  /// inspect it without losing the typed cause.
  const AuthException(
    String message, {
    super.originalError,
    super.stackTrace,
  }) : super(message: message);

  @override
  String toString() => 'AuthException: $message';
}

/// Outcome of a token refresh attempt — distinguishes success, an auth-class
/// failure, and a network-class failure (where the user must NOT be logged
/// out).
sealed class _RefreshOutcome {
  const _RefreshOutcome();
}

class _RefreshSuccess extends _RefreshOutcome {
  const _RefreshSuccess();
}

class _RefreshAuthFailure extends _RefreshOutcome {
  final Object? error;
  const _RefreshAuthFailure(this.error);
}

class _RefreshNetworkFailure extends _RefreshOutcome {
  final NetworkException exception;
  const _RefreshNetworkFailure(this.exception);
}
