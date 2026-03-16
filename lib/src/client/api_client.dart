import 'package:dio/dio.dart';

import 'api_client_config.dart';

/// A production-ready API client powered by Dio.
///
/// Create an instance with minimal configuration:
/// ```dart
/// final client = ApiClient(baseUrl: 'https://api.example.com');
/// ```
///
/// Or with full configuration:
/// ```dart
/// final client = ApiClient(
///   baseUrl: 'https://api.example.com',
///   connectTimeout: Duration(seconds: 60),
///   headers: {'Authorization': 'Bearer token'},
/// );
/// ```
class ApiClient {
  /// The underlying Dio instance.
  final Dio _dio;

  /// The configuration for this client.
  final ApiClientConfig config;

  /// Creates an [ApiClient] with the given [baseUrl].
  ///
  /// All timeout values default to 30 seconds.
  ///
  /// Example:
  /// ```dart
  /// final client = ApiClient(baseUrl: 'https://api.example.com');
  /// ```
  factory ApiClient({
    required String baseUrl,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    Duration sendTimeout = const Duration(seconds: 30),
    Map<String, dynamic>? headers,
    List<Interceptor>? interceptors,
  }) {
    final config = ApiClientConfig(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      headers: headers,
      interceptors: interceptors,
    );
    return ApiClient.fromConfig(config);
  }

  /// Creates an [ApiClient] from an [ApiClientConfig].
  ///
  /// Example:
  /// ```dart
  /// final config = ApiClientConfig(baseUrl: 'https://api.example.com');
  /// final client = ApiClient.fromConfig(config);
  /// ```
  ApiClient.fromConfig(this.config) : _dio = Dio() {
    _dio.options = BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      sendTimeout: config.sendTimeout,
      headers: config.headers,
    );

    if (config.interceptors != null) {
      _dio.interceptors.addAll(config.interceptors!);
    }
  }

  /// Creates an [ApiClient] with a custom [Dio] instance.
  ///
  /// Useful for testing or advanced customization.
  ApiClient.withDio(this._dio, this.config);

  /// The base URL for all requests.
  String get baseUrl => config.baseUrl;

  /// The underlying Dio instance for advanced usage.
  ///
  /// Prefer using the ApiClient methods when possible.
  Dio get dio => _dio;

  /// Closes the client and releases resources.
  void close({bool force = false}) {
    _dio.close(force: force);
  }
}
