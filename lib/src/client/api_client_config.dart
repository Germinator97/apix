import 'package:dio/dio.dart';

/// Configuration for ApiClient.
///
/// Example:
/// ```dart
/// final config = ApiClientConfig(
///   baseUrl: 'https://api.example.com',
///   timeout: Duration(seconds: 60),
///   headers: {'X-Custom': 'value'},
/// );
/// ```
class ApiClientConfig {
  /// The base URL for all requests.
  final String baseUrl;

  /// Connection timeout duration.
  ///
  /// Defaults to 30 seconds.
  final Duration connectTimeout;

  /// Receive timeout duration.
  ///
  /// Defaults to 30 seconds.
  final Duration receiveTimeout;

  /// Send timeout duration.
  ///
  /// Defaults to 30 seconds.
  final Duration sendTimeout;

  /// Default headers to include in all requests.
  final Map<String, dynamic>? headers;

  /// Default content type for requests.
  ///
  /// Defaults to 'application/json'. Set to null to disable auto content-type.
  /// This is automatically overridden when sending FormData (multipart).
  final String? defaultContentType;

  /// Custom Dio interceptors to add.
  final List<Interceptor>? interceptors;

  /// Creates an [ApiClientConfig].
  ///
  /// Only [baseUrl] is required. All other options have sensible defaults.
  const ApiClientConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.headers,
    this.defaultContentType = 'application/json',
    this.interceptors,
  });

  /// Creates a copy of this config with the given fields replaced.
  ApiClientConfig copyWith({
    String? baseUrl,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Map<String, dynamic>? headers,
    String? defaultContentType,
    List<Interceptor>? interceptors,
  }) {
    return ApiClientConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      headers: headers ?? this.headers,
      defaultContentType: defaultContentType ?? this.defaultContentType,
      interceptors: interceptors ?? this.interceptors,
    );
  }
}
