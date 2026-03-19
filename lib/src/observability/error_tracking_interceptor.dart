import 'package:dio/dio.dart';

/// Signature for capturing exceptions to an error tracking service.
typedef CaptureException = Future<void> Function(
  Object exception, {
  StackTrace? stackTrace,
  Map<String, dynamic>? extra,
  Map<String, String>? tags,
});

/// Signature for adding breadcrumbs to an error tracking service.
typedef AddBreadcrumb = void Function(Map<String, dynamic> data);

/// Configuration for the error tracking interceptor.
///
/// This interceptor is designed to be error-tracking agnostic.
/// It works with Sentry, Crashlytics, or any other service via callbacks.
///
/// Example with Sentry:
/// ```dart
/// final config = ErrorTrackingConfig(
///   onError: (exception, {stackTrace, extra, tags}) async {
///     await Sentry.captureException(
///       exception,
///       stackTrace: stackTrace,
///       withScope: (scope) {
///         extra?.forEach((key, value) => scope.setExtra(key, value));
///         tags?.forEach((key, value) => scope.setTag(key, value));
///       },
///     );
///   },
///   onBreadcrumb: (data) {
///     Sentry.addBreadcrumb(Breadcrumb(
///       message: data['message'] as String?,
///       category: data['category'] as String?,
///       data: data['data'] as Map<String, dynamic>?,
///       level: SentryLevel.info,
///     ));
///   },
/// );
/// ```
///
/// Example with Firebase Crashlytics:
/// ```dart
/// final config = ErrorTrackingConfig(
///   onError: (exception, {stackTrace, extra, tags}) async {
///     await FirebaseCrashlytics.instance.recordError(
///       exception,
///       stackTrace,
///       reason: extra?['message'],
///     );
///   },
/// );
/// ```
class ErrorTrackingConfig {
  /// Whether error capturing is enabled.
  final bool enabled;

  /// Environment name (e.g., 'production', 'staging', 'development').
  final String? environment;

  /// Callback to capture exceptions.
  final CaptureException? onError;

  /// Callback to add breadcrumbs.
  final AddBreadcrumb? onBreadcrumb;

  /// HTTP status codes that should be captured as errors.
  /// Defaults to 5xx errors only.
  final Set<int> captureStatusCodes;

  /// Whether to capture request body in error context.
  final bool captureRequestBody;

  /// Whether to capture response body in error context.
  final bool captureResponseBody;

  /// Headers to redact from error context.
  final List<String> redactedHeaders;

  /// Maximum body length to capture.
  final int maxBodyLength;

  const ErrorTrackingConfig({
    this.enabled = true,
    this.environment,
    this.onError,
    this.onBreadcrumb,
    this.captureStatusCodes = const {500, 501, 502, 503, 504},
    this.captureRequestBody = false,
    this.captureResponseBody = true,
    this.redactedHeaders = const ['Authorization', 'Cookie', 'Set-Cookie'],
    this.maxBodyLength = 1024,
  });

  /// Creates a disabled config.
  factory ErrorTrackingConfig.disabled() =>
      const ErrorTrackingConfig(enabled: false);

  /// Redacts sensitive headers.
  Map<String, dynamic> redactHeaders(Map<String, dynamic> headers) {
    final result = Map<String, dynamic>.from(headers);
    for (final key in result.keys.toList()) {
      if (redactedHeaders.any((h) => h.toLowerCase() == key.toLowerCase())) {
        result[key] = '[REDACTED]';
      }
    }
    return result;
  }

  /// Truncates body if too long.
  String truncateBody(dynamic body) {
    if (body == null) return 'null';
    final str = body.toString();
    if (str.length <= maxBodyLength) return str;
    return '${str.substring(0, maxBodyLength)}... [truncated]';
  }
}

/// Interceptor that captures API errors to error tracking services.
///
/// This interceptor:
/// - Captures DioExceptions and HTTP errors to your error tracking service
/// - Adds request breadcrumbs for debugging
/// - Includes request context (URL, method, headers) in error reports
///
/// Example:
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(ErrorTrackingInterceptor(
///   config: ErrorTrackingConfig(
///     environment: 'production',
///     onError: (e, {stackTrace, extra, tags}) async {
///       await Sentry.captureException(e, stackTrace: stackTrace);
///     },
///   ),
/// ));
/// ```
class ErrorTrackingInterceptor extends Interceptor {
  /// Configuration for error capturing.
  final ErrorTrackingConfig config;

  ErrorTrackingInterceptor({
    ErrorTrackingConfig? config,
  }) : config = config ?? const ErrorTrackingConfig();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (config.enabled && config.onBreadcrumb != null) {
      _addRequestBreadcrumb(options);
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (config.enabled && config.onBreadcrumb != null) {
      _addResponseBreadcrumb(response);
    }

    // Capture specific status codes as errors
    if (config.enabled &&
        config.onError != null &&
        response.statusCode != null &&
        config.captureStatusCodes.contains(response.statusCode)) {
      _captureHttpError(response);
    }

    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    if (config.enabled && config.onError != null) {
      _captureException(err);
    }
    handler.next(err);
  }

  void _addRequestBreadcrumb(RequestOptions options) {
    config.onBreadcrumb!({
      'message': '${options.method} ${options.uri}',
      'category': 'http',
      'type': 'http',
      'data': {
        'method': options.method,
        'url': options.uri.toString(),
        if (config.captureRequestBody && options.data != null)
          'request_body': config.truncateBody(options.data),
      },
    });
  }

  void _addResponseBreadcrumb(Response<dynamic> response) {
    final options = response.requestOptions;
    config.onBreadcrumb!({
      'message': '${options.method} ${options.uri} [${response.statusCode}]',
      'category': 'http',
      'type': 'http',
      'data': {
        'method': options.method,
        'url': options.uri.toString(),
        'status_code': response.statusCode,
        'reason': response.statusMessage,
      },
    });
  }

  void _captureHttpError(Response<dynamic> response) {
    final options = response.requestOptions;

    final exception = HttpTrackingException(
      statusCode: response.statusCode!,
      message: response.statusMessage ?? 'HTTP Error',
      url: options.uri.toString(),
      method: options.method,
    );

    config.onError!(
      exception,
      extra: _buildErrorContext(options, response),
      tags: _buildTags(options, response.statusCode),
    );
  }

  void _captureException(DioException err) {
    final options = err.requestOptions;

    config.onError!(
      err,
      stackTrace: err.stackTrace,
      extra: _buildErrorContext(options, err.response),
      tags: _buildTags(options, err.response?.statusCode),
    );
  }

  Map<String, dynamic> _buildErrorContext(
    RequestOptions options,
    Response<dynamic>? response,
  ) {
    return {
      'method': options.method,
      'url': options.uri.toString(),
      'path': options.path,
      'headers':
          config.redactHeaders(Map<String, dynamic>.from(options.headers)),
      if (config.captureRequestBody && options.data != null)
        'request_body': config.truncateBody(options.data),
      if (response != null) ...{
        'status_code': response.statusCode,
        'status_message': response.statusMessage,
        if (config.captureResponseBody && response.data != null)
          'response_body': config.truncateBody(response.data),
      },
      if (config.environment != null) 'environment': config.environment,
    };
  }

  Map<String, String> _buildTags(RequestOptions options, int? statusCode) {
    return {
      'http.method': options.method,
      'http.url': options.uri.host,
      if (statusCode != null) 'http.status_code': statusCode.toString(),
      if (config.environment != null) 'environment': config.environment!,
    };
  }
}

/// Exception representing an HTTP error captured by error tracking.
class HttpTrackingException implements Exception {
  /// HTTP status code.
  final int statusCode;

  /// Error message.
  final String message;

  /// Request URL.
  final String url;

  /// HTTP method.
  final String method;

  const HttpTrackingException({
    required this.statusCode,
    required this.message,
    required this.url,
    required this.method,
  });

  @override
  String toString() =>
      'HttpTrackingException: $method $url [$statusCode] $message';
}
