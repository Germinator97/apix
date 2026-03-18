import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_client_config.dart';
import 'multipart_interceptor.dart';

/// Factory for creating [ApiClient] instances.
///
/// Example:
/// ```dart
/// final client = ApiClientFactory.create(baseUrl: 'https://api.example.com');
/// ```
class ApiClientFactory {
  ApiClientFactory._();

  /// Creates an [ApiClient] with the given [baseUrl].
  ///
  /// All timeout values default to 30 seconds.
  ///
  /// Example:
  /// ```dart
  /// final client = ApiClientFactory.create(baseUrl: 'https://api.example.com');
  /// ```
  static ApiClient create({
    required String baseUrl,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    Duration sendTimeout = const Duration(seconds: 30),
    String? defaultContentType = 'application/json',
    Map<String, dynamic>? headers,
    List<Interceptor>? interceptors,
    HttpClientAdapter? httpClientAdapter,
  }) {
    final config = ApiClientConfig(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      defaultContentType: defaultContentType,
      headers: headers,
      interceptors: interceptors,
    );
    return fromConfig(config, httpClientAdapter: httpClientAdapter);
  }

  /// Creates an [ApiClient] from an [ApiClientConfig].
  ///
  /// Example:
  /// ```dart
  /// final config = ApiClientConfig(baseUrl: 'https://api.example.com');
  /// final client = ApiClientFactory.fromConfig(config);
  /// ```
  static ApiClient fromConfig(
    ApiClientConfig config, {
    HttpClientAdapter? httpClientAdapter,
  }) {
    final dio = Dio();

    dio.options = BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      sendTimeout: config.sendTimeout,
      headers: config.headers,
    );

    // Custom HTTP client adapter (optional)
    if (httpClientAdapter != null) {
      dio.httpClientAdapter = httpClientAdapter;
    }

    // Add multipart interceptor for auto-detection of files
    dio.interceptors.add(
      MultipartInterceptor(defaultContentType: config.defaultContentType),
    );

    if (config.interceptors != null) {
      dio.interceptors.addAll(config.interceptors!);
    }

    return ApiClient(dio, config);
  }
}
