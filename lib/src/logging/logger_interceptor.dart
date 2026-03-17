import 'package:dio/dio.dart';

import 'logger_config.dart';

/// Interceptor that logs HTTP requests and responses.
///
/// Example:
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(LoggerInterceptor(
///   config: LoggerConfig.debug(),
/// ));
/// ```
class LoggerInterceptor extends Interceptor {
  /// Configuration for the logger.
  final LoggerConfig config;

  LoggerInterceptor({
    LoggerConfig? config,
  }) : config = config ?? const LoggerConfig();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    options.recordStartTime();

    if (config.shouldLog(LogLevel.info)) {
      _logRequest(options);
    }

    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (config.shouldLog(LogLevel.info)) {
      _logResponse(response);
    }

    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    if (config.logErrors && config.shouldLog(LogLevel.error)) {
      _logError(err);
    }

    handler.next(err);
  }

  void _logRequest(RequestOptions options) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      message: '→ Request',
      method: options.method,
      url: options.uri.toString(),
      headers: config.logRequestHeaders
          ? config.redactHeaders(Map<String, dynamic>.from(options.headers))
          : null,
      body: config.logRequestBody ? options.data : null,
    );

    _emit(entry);

    if (config.level == LogLevel.trace) {
      _printRequestDetails(options);
    }
  }

  void _logResponse(Response<dynamic> response) {
    final options = response.requestOptions;
    final durationMs = options.durationMs;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      message: '← Response',
      method: options.method,
      url: options.uri.toString(),
      statusCode: response.statusCode,
      durationMs: durationMs,
      headers: config.logResponseHeaders
          ? config.redactHeaders(
              Map<String, dynamic>.from(response.headers.map),
            )
          : null,
      body: config.logResponseBody ? response.data : null,
    );

    _emit(entry);

    if (config.level == LogLevel.trace) {
      _printResponseDetails(response);
    }
  }

  void _logError(DioException err) {
    final options = err.requestOptions;
    final durationMs = options.durationMs;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.error,
      message: '✖ Error',
      method: options.method,
      url: options.uri.toString(),
      statusCode: err.response?.statusCode,
      durationMs: durationMs,
      error: err.message ?? err.error?.toString(),
      body: err.response?.data,
      extra: {
        'type': err.type.name,
      },
    );

    _emit(entry);

    if (config.level == LogLevel.trace) {
      _printErrorDetails(err);
    }
  }

  void _emit(LogEntry entry) {
    if (config.logHandler != null) {
      config.logHandler!(entry);
    } else {
      _defaultPrint(entry);
    }
  }

  void _defaultPrint(LogEntry entry) {
    final buffer = StringBuffer();

    if (config.includeTimestamp) {
      buffer.write('[${_formatTime(entry.timestamp)}] ');
    }

    buffer.write(entry.message);

    if (entry.method != null) {
      buffer.write(' ${entry.method}');
    }
    if (entry.url != null) {
      buffer.write(' ${entry.url}');
    }
    if (entry.statusCode != null) {
      buffer.write(' [${entry.statusCode}]');
    }
    if (entry.durationMs != null) {
      buffer.write(' (${entry.durationMs}ms)');
    }
    if (entry.error != null) {
      buffer.write(' - ${entry.error}');
    }

    // ignore: avoid_print
    print(buffer.toString());
  }

  void _printRequestDetails(RequestOptions options) {
    if (config.logRequestHeaders && options.headers.isNotEmpty) {
      final redacted = config.redactHeaders(
        Map<String, dynamic>.from(options.headers),
      );
      // ignore: avoid_print
      print('  Headers: $redacted');
    }

    if (config.logRequestBody && options.data != null) {
      // ignore: avoid_print
      print('  Body: ${config.truncateBody(options.data)}');
    }
  }

  void _printResponseDetails(Response<dynamic> response) {
    if (config.logResponseHeaders && response.headers.map.isNotEmpty) {
      final redacted = config.redactHeaders(
        Map<String, dynamic>.from(response.headers.map),
      );
      // ignore: avoid_print
      print('  Headers: $redacted');
    }

    if (config.logResponseBody && response.data != null) {
      // ignore: avoid_print
      print('  Body: ${config.truncateBody(response.data)}');
    }
  }

  void _printErrorDetails(DioException err) {
    // ignore: avoid_print
    print('  Type: ${err.type.name}');
    if (err.message != null) {
      // ignore: avoid_print
      print('  Message: ${err.message}');
    }
    if (err.response?.data != null) {
      // ignore: avoid_print
      print('  Response: ${config.truncateBody(err.response?.data)}');
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}
