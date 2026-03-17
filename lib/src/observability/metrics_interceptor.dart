import 'package:dio/dio.dart';

/// Request metrics data.
class RequestMetrics {
  /// Unique request identifier.
  final String requestId;

  /// HTTP method.
  final String method;

  /// Request URL.
  final String url;

  /// Request path.
  final String path;

  /// Request start time.
  final DateTime startTime;

  /// Request end time (null if still in progress).
  final DateTime? endTime;

  /// Request duration in milliseconds (null if still in progress).
  final int? durationMs;

  /// HTTP status code (null if failed before response).
  final int? statusCode;

  /// Whether the request succeeded.
  final bool success;

  /// Error message if failed.
  final String? error;

  /// Error type if failed.
  final String? errorType;

  /// Request size in bytes (if available).
  final int? requestSize;

  /// Response size in bytes (if available).
  final int? responseSize;

  /// Additional metadata.
  final Map<String, dynamic> extra;

  const RequestMetrics({
    required this.requestId,
    required this.method,
    required this.url,
    required this.path,
    required this.startTime,
    this.endTime,
    this.durationMs,
    this.statusCode,
    this.success = true,
    this.error,
    this.errorType,
    this.requestSize,
    this.responseSize,
    this.extra = const {},
  });

  /// Creates a copy with updated fields.
  RequestMetrics copyWith({
    DateTime? endTime,
    int? durationMs,
    int? statusCode,
    bool? success,
    String? error,
    String? errorType,
    int? responseSize,
    Map<String, dynamic>? extra,
  }) {
    return RequestMetrics(
      requestId: requestId,
      method: method,
      url: url,
      path: path,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      durationMs: durationMs ?? this.durationMs,
      statusCode: statusCode ?? this.statusCode,
      success: success ?? this.success,
      error: error ?? this.error,
      errorType: errorType ?? this.errorType,
      requestSize: requestSize,
      responseSize: responseSize ?? this.responseSize,
      extra: extra ?? this.extra,
    );
  }

  /// Converts to a map for breadcrumb data.
  Map<String, dynamic> toMap() {
    return {
      'request_id': requestId,
      'method': method,
      'url': url,
      'path': path,
      'start_time': startTime.toIso8601String(),
      if (endTime != null) 'end_time': endTime!.toIso8601String(),
      if (durationMs != null) 'duration_ms': durationMs,
      if (statusCode != null) 'status_code': statusCode,
      'success': success,
      if (error != null) 'error': error,
      if (errorType != null) 'error_type': errorType,
      if (requestSize != null) 'request_size': requestSize,
      if (responseSize != null) 'response_size': responseSize,
      if (extra.isNotEmpty) ...extra,
    };
  }

  @override
  String toString() {
    final status = statusCode != null ? '[$statusCode]' : '';
    final duration = durationMs != null ? '${durationMs}ms' : 'pending';
    return 'RequestMetrics($method $path $status $duration)';
  }
}

/// Breadcrumb data for request tracking.
class RequestBreadcrumb {
  /// Breadcrumb type.
  final BreadcrumbType type;

  /// Breadcrumb message.
  final String message;

  /// Breadcrumb category.
  final String category;

  /// Timestamp.
  final DateTime timestamp;

  /// Breadcrumb data.
  final Map<String, dynamic> data;

  const RequestBreadcrumb({
    required this.type,
    required this.message,
    required this.category,
    required this.timestamp,
    this.data = const {},
  });

  /// Converts to a map.
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'message': message,
      'category': category,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
    };
  }
}

/// Breadcrumb types.
enum BreadcrumbType {
  /// HTTP request started.
  request,

  /// HTTP response received.
  response,

  /// HTTP error occurred.
  error,
}

/// Signature for metrics handler.
typedef MetricsHandler = void Function(RequestMetrics metrics);

/// Signature for breadcrumb handler.
typedef BreadcrumbHandler = void Function(RequestBreadcrumb breadcrumb);

/// Configuration for the metrics interceptor.
class MetricsConfig {
  /// Whether metrics collection is enabled.
  final bool enabled;

  /// Handler for completed request metrics.
  final MetricsHandler? onMetrics;

  /// Handler for breadcrumbs.
  final BreadcrumbHandler? onBreadcrumb;

  /// Whether to include request size in metrics.
  final bool trackRequestSize;

  /// Whether to include response size in metrics.
  final bool trackResponseSize;

  /// Custom request ID generator.
  final String Function()? requestIdGenerator;

  const MetricsConfig({
    this.enabled = true,
    this.onMetrics,
    this.onBreadcrumb,
    this.trackRequestSize = false,
    this.trackResponseSize = false,
    this.requestIdGenerator,
  });

  /// Creates a disabled config.
  factory MetricsConfig.disabled() => const MetricsConfig(enabled: false);
}

/// Interceptor that tracks request metrics and breadcrumbs.
///
/// Example:
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(MetricsInterceptor(
///   config: MetricsConfig(
///     onMetrics: (metrics) {
///       analytics.track('api_request', metrics.toMap());
///     },
///     onBreadcrumb: (breadcrumb) {
///       Sentry.addBreadcrumb(Breadcrumb(
///         message: breadcrumb.message,
///         category: breadcrumb.category,
///         data: breadcrumb.data,
///       ));
///     },
///   ),
/// ));
/// ```
class MetricsInterceptor extends Interceptor {
  /// Configuration for metrics.
  final MetricsConfig config;

  /// In-flight requests metrics.
  final Map<String, RequestMetrics> _inFlight = {};

  MetricsInterceptor({
    MetricsConfig? config,
  }) : config = config ?? const MetricsConfig();

  /// Returns current in-flight requests.
  Map<String, RequestMetrics> get inFlightRequests =>
      Map.unmodifiable(_inFlight);

  /// Returns count of in-flight requests.
  int get inFlightCount => _inFlight.length;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (config.enabled) {
      final metrics = _createMetrics(options);
      _inFlight[metrics.requestId] = metrics;
      options.extra['_metrics_request_id'] = metrics.requestId;

      _emitBreadcrumb(
        type: BreadcrumbType.request,
        message: '→ ${options.method} ${options.path}',
        data: {
          'method': options.method,
          'url': options.uri.toString(),
          'path': options.path,
        },
      );
    }

    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (config.enabled) {
      final requestId = response.requestOptions.extra['_metrics_request_id'];
      if (requestId != null) {
        final metrics = _completeMetrics(
          requestId: requestId as String,
          statusCode: response.statusCode,
          success: true,
          responseSize: _getResponseSize(response),
        );

        if (metrics != null) {
          config.onMetrics?.call(metrics);
        }

        _emitBreadcrumb(
          type: BreadcrumbType.response,
          message:
              '← ${response.requestOptions.method} ${response.requestOptions.path} [${response.statusCode}]',
          data: {
            'method': response.requestOptions.method,
            'url': response.requestOptions.uri.toString(),
            'status_code': response.statusCode,
            if (metrics != null) 'duration_ms': metrics.durationMs,
          },
        );
      }
    }

    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    if (config.enabled) {
      final requestId = err.requestOptions.extra['_metrics_request_id'];
      if (requestId != null) {
        final metrics = _completeMetrics(
          requestId: requestId as String,
          statusCode: err.response?.statusCode,
          success: false,
          error: err.message ?? err.error?.toString(),
          errorType: err.type.name,
          responseSize:
              err.response != null ? _getResponseSize(err.response!) : null,
        );

        if (metrics != null) {
          config.onMetrics?.call(metrics);
        }

        _emitBreadcrumb(
          type: BreadcrumbType.error,
          message:
              '✖ ${err.requestOptions.method} ${err.requestOptions.path} [${err.type.name}]',
          data: {
            'method': err.requestOptions.method,
            'url': err.requestOptions.uri.toString(),
            'error_type': err.type.name,
            if (err.response?.statusCode != null)
              'status_code': err.response!.statusCode,
            if (err.message != null) 'error': err.message,
            if (metrics != null) 'duration_ms': metrics.durationMs,
          },
        );
      }
    }

    handler.next(err);
  }

  RequestMetrics _createMetrics(RequestOptions options) {
    final requestId = config.requestIdGenerator?.call() ?? _generateRequestId();
    final now = DateTime.now();

    return RequestMetrics(
      requestId: requestId,
      method: options.method,
      url: options.uri.toString(),
      path: options.path,
      startTime: now,
      requestSize: config.trackRequestSize ? _getRequestSize(options) : null,
    );
  }

  RequestMetrics? _completeMetrics({
    required String requestId,
    int? statusCode,
    required bool success,
    String? error,
    String? errorType,
    int? responseSize,
  }) {
    final metrics = _inFlight.remove(requestId);
    if (metrics == null) return null;

    final endTime = DateTime.now();
    final durationMs = endTime.difference(metrics.startTime).inMilliseconds;

    return metrics.copyWith(
      endTime: endTime,
      durationMs: durationMs,
      statusCode: statusCode,
      success: success,
      error: error,
      errorType: errorType,
      responseSize: responseSize,
    );
  }

  void _emitBreadcrumb({
    required BreadcrumbType type,
    required String message,
    required Map<String, dynamic> data,
  }) {
    if (config.onBreadcrumb == null) return;

    config.onBreadcrumb!(RequestBreadcrumb(
      type: type,
      message: message,
      category: 'http',
      timestamp: DateTime.now(),
      data: data,
    ));
  }

  String _generateRequestId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_inFlight.length}';
  }

  int? _getRequestSize(RequestOptions options) {
    if (options.data == null) return null;
    try {
      return options.data.toString().length;
    } catch (_) {
      return null;
    }
  }

  int? _getResponseSize(Response<dynamic> response) {
    if (!config.trackResponseSize) return null;
    if (response.data == null) return null;
    try {
      return response.data.toString().length;
    } catch (_) {
      return null;
    }
  }
}
