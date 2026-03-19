import 'package:dio/dio.dart';

import '../auth/auth_config.dart';
import '../auth/auth_interceptor.dart';
import '../cache/cache_config.dart';
import '../cache/cache_interceptor.dart';
import '../logging/logger_config.dart';
import '../logging/logger_interceptor.dart';
import '../observability/error_tracking_interceptor.dart';
import '../observability/metrics_interceptor.dart';
import '../retry/retry_config.dart';
import '../retry/retry_interceptor.dart';
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
  /// final tokenProvider = SecureTokenProvider();
  /// final client = ApiClientFactory.create(
  ///   baseUrl: 'https://api.example.com',
  ///   authConfig: AuthConfig(
  ///     tokenProvider: tokenProvider,
  ///     refreshEndpoint: '/auth/refresh',
  ///     onTokenRefreshed: (response) async {
  ///       await tokenProvider.saveTokens(
  ///         response.data['access_token'],
  ///         response.data['refresh_token'],
  ///       );
  ///     },
  ///   ),
  ///   retryConfig: const RetryConfig(),
  /// );
  /// ```
  static ApiClient create({
    required String baseUrl,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    Duration sendTimeout = const Duration(seconds: 30),
    String? defaultContentType = 'application/json',
    Map<String, dynamic>? headers,
    AuthConfig? authConfig,
    RetryConfig? retryConfig,
    CacheConfig? cacheConfig,
    LoggerConfig? loggerConfig,
    ErrorTrackingConfig? errorTrackingConfig,
    MetricsConfig? metricsConfig,
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
    return fromConfig(
      config,
      authConfig: authConfig,
      retryConfig: retryConfig,
      cacheConfig: cacheConfig,
      loggerConfig: loggerConfig,
      errorTrackingConfig: errorTrackingConfig,
      metricsConfig: metricsConfig,
      httpClientAdapter: httpClientAdapter,
    );
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
    AuthConfig? authConfig,
    RetryConfig? retryConfig,
    CacheConfig? cacheConfig,
    LoggerConfig? loggerConfig,
    ErrorTrackingConfig? errorTrackingConfig,
    MetricsConfig? metricsConfig,
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

    // Add auth interceptor if configured
    if (authConfig != null) {
      dio.interceptors.add(AuthInterceptor(authConfig, dio));
    }

    // Add retry interceptor if configured
    if (retryConfig != null) {
      dio.interceptors.add(RetryInterceptor(config: retryConfig, dio: dio));
    }

    // Add cache interceptor if configured
    if (cacheConfig != null) {
      final cacheInterceptor = CacheInterceptor(config: cacheConfig);
      cacheInterceptor.setDio(dio);
      dio.interceptors.add(cacheInterceptor);
    }

    // Add logger interceptor if configured
    if (loggerConfig != null) {
      dio.interceptors.add(LoggerInterceptor(config: loggerConfig));
    }

    // Add error tracking interceptor if configured
    if (errorTrackingConfig != null) {
      dio.interceptors
          .add(ErrorTrackingInterceptor(config: errorTrackingConfig));
    }

    // Add metrics interceptor if configured
    if (metricsConfig != null) {
      dio.interceptors.add(MetricsInterceptor(config: metricsConfig));
    }

    // Add custom interceptors
    if (config.interceptors != null) {
      dio.interceptors.addAll(config.interceptors!);
    }

    return ApiClient(dio, config);
  }
}
