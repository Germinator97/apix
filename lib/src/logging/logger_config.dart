import 'package:dio/dio.dart';

/// Log level for filtering log output.
enum LogLevel {
  /// No logging.
  none,

  /// Log only errors.
  error,

  /// Log errors and warnings.
  warn,

  /// Log errors, warnings, and info.
  info,

  /// Log everything including trace details.
  trace,
}

/// Extension to add emoji prefixes to log levels.
extension LogLevelExtension on LogLevel {
  /// Returns the emoji prefix for this log level.
  String get prefix {
    switch (this) {
      case LogLevel.none:
        return '';
      case LogLevel.error:
        return '[❌ ERROR 🔥]';
      case LogLevel.warn:
        return '[⚠️ WARN ⚡]';
      case LogLevel.info:
        return '[ℹ️ INFO 💡]';
      case LogLevel.trace:
        return '[🔍 TRACE 🐛]';
    }
  }
}

/// Structured log entry for request/response logging.
class LogEntry {
  /// Timestamp of the log entry.
  final DateTime timestamp;

  /// Log level.
  final LogLevel level;

  /// Log message.
  final String message;

  /// HTTP method (GET, POST, etc.).
  final String? method;

  /// Request URL.
  final String? url;

  /// HTTP status code.
  final int? statusCode;

  /// Request/response duration in milliseconds.
  final int? durationMs;

  /// Request headers.
  final Map<String, dynamic>? headers;

  /// Request/response body.
  final dynamic body;

  /// Error if any.
  final Object? error;

  /// Additional context data.
  final Map<String, dynamic>? extra;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.method,
    this.url,
    this.statusCode,
    this.durationMs,
    this.headers,
    this.body,
    this.error,
    this.extra,
  });

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write('${level.prefix} ')
      ..write(message);

    if (method != null && url != null) {
      buffer.write(' $method $url');
    }
    if (statusCode != null) {
      buffer.write(' ($statusCode)');
    }
    if (durationMs != null) {
      buffer.write(' ${durationMs}ms');
    }

    return buffer.toString();
  }
}

/// Signature for custom log handlers.
typedef LogHandler = void Function(LogEntry entry);

/// Configuration for the logger interceptor.
class LoggerConfig {
  /// Whether logging is enabled.
  final bool enabled;

  /// Minimum log level to output.
  final LogLevel level;

  /// Whether to log request headers.
  final bool logRequestHeaders;

  /// Whether to log request body.
  final bool logRequestBody;

  /// Whether to log response headers.
  final bool logResponseHeaders;

  /// Whether to log response body.
  final bool logResponseBody;

  /// Whether to log errors.
  final bool logErrors;

  /// Maximum body length to log (truncates if exceeded).
  final int maxBodyLength;

  /// Headers to redact from logs (e.g., Authorization).
  final List<String> redactedHeaders;

  /// Custom log handler. If null, uses default print-based logging.
  final LogHandler? logHandler;

  /// Whether to include timestamps in default log output.
  final bool includeTimestamp;

  const LoggerConfig({
    this.enabled = true,
    this.level = LogLevel.info,
    this.logRequestHeaders = true,
    this.logRequestBody = true,
    this.logResponseHeaders = false,
    this.logResponseBody = true,
    this.logErrors = true,
    this.maxBodyLength = 1024,
    this.redactedHeaders = const ['Authorization', 'Cookie', 'Set-Cookie'],
    this.logHandler,
    this.includeTimestamp = false,
  });

  /// Creates a config suitable for debug/development mode.
  factory LoggerConfig.trace() => const LoggerConfig(
        level: LogLevel.trace,
        logRequestHeaders: true,
        logRequestBody: true,
        logResponseHeaders: true,
        logResponseBody: true,
        includeTimestamp: true,
      );

  /// Creates a minimal config for production.
  factory LoggerConfig.minimal() => const LoggerConfig(
        level: LogLevel.error,
        logRequestHeaders: false,
        logRequestBody: false,
        logResponseHeaders: false,
        logResponseBody: false,
      );

  /// Creates a disabled config.
  factory LoggerConfig.disabled() => const LoggerConfig(enabled: false);

  /// Returns true if the given level should be logged.
  bool shouldLog(LogLevel logLevel) {
    if (!enabled) return false;
    return logLevel.index <= level.index && logLevel != LogLevel.none;
  }

  /// Redacts sensitive headers from a headers map.
  Map<String, dynamic> redactHeaders(Map<String, dynamic> headers) {
    final result = Map<String, dynamic>.from(headers);
    for (final header in redactedHeaders) {
      final lowerHeader = header.toLowerCase();
      for (final key in result.keys.toList()) {
        if (key.toLowerCase() == lowerHeader) {
          result[key] = '[REDACTED]';
        }
      }
    }
    return result;
  }

  /// Truncates body if it exceeds maxBodyLength.
  String truncateBody(dynamic body) {
    if (body == null) return 'null';

    final str = body.toString();
    if (str.length <= maxBodyLength) return str;

    return '${str.substring(0, maxBodyLength)}... [truncated]';
  }

  /// Creates a copy with updated values.
  LoggerConfig copyWith({
    bool? enabled,
    LogLevel? level,
    bool? logRequestHeaders,
    bool? logRequestBody,
    bool? logResponseHeaders,
    bool? logResponseBody,
    bool? logErrors,
    int? maxBodyLength,
    List<String>? redactedHeaders,
    LogHandler? logHandler,
    bool? includeTimestamp,
  }) {
    return LoggerConfig(
      enabled: enabled ?? this.enabled,
      level: level ?? this.level,
      logRequestHeaders: logRequestHeaders ?? this.logRequestHeaders,
      logRequestBody: logRequestBody ?? this.logRequestBody,
      logResponseHeaders: logResponseHeaders ?? this.logResponseHeaders,
      logResponseBody: logResponseBody ?? this.logResponseBody,
      logErrors: logErrors ?? this.logErrors,
      maxBodyLength: maxBodyLength ?? this.maxBodyLength,
      redactedHeaders: redactedHeaders ?? this.redactedHeaders,
      logHandler: logHandler ?? this.logHandler,
      includeTimestamp: includeTimestamp ?? this.includeTimestamp,
    );
  }
}

/// Extension to attach timing data to requests.
extension LoggerRequestExtension on RequestOptions {
  static const _startTimeKey = '_loggerStartTime';

  /// Records the start time for duration calculation.
  void recordStartTime() {
    extra[_startTimeKey] = DateTime.now().millisecondsSinceEpoch;
  }

  /// Returns the start time if recorded.
  int? get startTime => extra[_startTimeKey] as int?;

  /// Calculates duration since start time.
  int? get durationMs {
    final start = startTime;
    if (start == null) return null;
    return DateTime.now().millisecondsSinceEpoch - start;
  }
}
