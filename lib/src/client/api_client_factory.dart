import 'package:dio/dio.dart';

import '../auth/auth_config.dart';
import '../auth/auth_interceptor.dart';
import '../cache/cache_config.dart';
import '../cache/cache_interceptor.dart';
import '../cache/deduplication_config.dart';
import '../cache/deduplication_interceptor.dart';
import '../errors/error_mapper_interceptor.dart';
import '../logging/logger_config.dart';
import '../logging/logger_interceptor.dart';
import '../observability/error_tracking_interceptor.dart';
import '../observability/metrics_interceptor.dart';
import '../retry/retry_config.dart';
import '../retry/retry_interceptor.dart';
import 'api_client.dart';
import 'api_client_config.dart';
import 'multipart_interceptor.dart';
import 'response_validator_interceptor.dart';

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
    void Function(RetryAttempt attempt)? onRetry,
    CacheConfig? cacheConfig,
    DeduplicationConfig? deduplicationConfig,
    LoggerConfig? loggerConfig,
    ErrorTrackingConfig? errorTrackingConfig,
    MetricsConfig? metricsConfig,
    List<Interceptor>? interceptors,
    HttpClientAdapter? httpClientAdapter,
    String dataKey = 'data',
    String errorCodeKey = 'code',
    bool strictContentType = false,
    ResponseValidator? responseValidator,
  }) {
    final config = ApiClientConfig(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      defaultContentType: defaultContentType,
      headers: headers,
      interceptors: interceptors,
      dataKey: dataKey,
      errorCodeKey: errorCodeKey,
      strictContentType: strictContentType,
      responseValidator: responseValidator,
    );
    return fromConfig(
      config,
      authConfig: authConfig,
      retryConfig: retryConfig,
      onRetry: onRetry,
      cacheConfig: cacheConfig,
      deduplicationConfig: deduplicationConfig,
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
    void Function(RetryAttempt attempt)? onRetry,
    CacheConfig? cacheConfig,
    DeduplicationConfig? deduplicationConfig,
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
      dio.interceptors.add(
        RetryInterceptor(config: retryConfig, dio: dio, onRetry: onRetry),
      );
    }

    // Add standalone deduplication if configured. Deliberately placed before
    // the cache: a cache hit should not pay for a deduplication round-trip.
    if (deduplicationConfig != null) {
      final dedupInterceptor =
          DeduplicationInterceptor(config: deduplicationConfig);
      dedupInterceptor.setDio(dio);
      dio.interceptors.add(dedupInterceptor);
    }

    // Add cache interceptor if configured
    if (cacheConfig != null) {
      // When standalone deduplication is wired in, the cache must not
      // deduplicate as well — two deduplicators in the same chain collapse the
      // same request twice, and the inner one would re-enter a chain the outer
      // one already resolved.
      final effectiveCacheConfig = deduplicationConfig == null
          ? cacheConfig
          : cacheConfig.copyWith(enableDeduplication: false);
      final cacheInterceptor = CacheInterceptor(config: effectiveCacheConfig);
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

    // Add response validator if configured (fires on 2xx; rejected
    // responses fall through to ErrorMapperInterceptor below)
    if (config.responseValidator != null) {
      dio.interceptors
          .add(ResponseValidatorInterceptor(config.responseValidator!));
    }

    // Add custom interceptors
    if (config.interceptors != null) {
      dio.interceptors.addAll(config.interceptors!);
    }

    // Add error mapper interceptor last to transform all DioExceptions
    // into typed ApiExceptions. It reads the application error code from the
    // body key the config names, so `ApiException.code` is populated for every
    // consumer that goes through the factory — not only those who wire the
    // mapper by hand.
    dio.interceptors.add(ErrorMapperInterceptor(
      errorCodeKey: config.errorCodeKey,
    ));

    return ApiClient(dio, config);
  }
}
