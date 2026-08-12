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
import '../observability/tracing_interceptor.dart';
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
    TracingConfig? tracingConfig,
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
      tracingConfig: tracingConfig,
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
    TracingConfig? tracingConfig,
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

    // Add the response validator BEFORE the cache and before every observer.
    //
    // Before the cache, because a 2xx body the validator refuses must never be
    // stored: a later cache hit resolves from `onRequest` and skips response
    // interceptors, so a stored business failure would come back unvalidated,
    // as a success.
    //
    // Before the observers, because `MetricsInterceptor.onResponse` would
    // otherwise have already recorded `success: true` and released its
    // in-flight entry — counting as fine the exact failures this feature
    // exists to surface — and error tracking would never see them at all.
    if (config.responseValidator != null) {
      dio.interceptors
          .add(ResponseValidatorInterceptor(config.responseValidator!));
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

    // Everything below sits AFTER the cache, deliberately — and the same
    // sentence has to be read for all three of them, not just for tracing.
    //
    // A cache hit resolves from `onRequest`, which ends the chain here. A span
    // opened before the cache would therefore never be closed, leaking on
    // exactly the requests that were fastest; that is why tracing is placed
    // below. But the logger and the metrics inherit the other half of the same
    // fact: **a cache hit produces no log line and no metric at all.** Measured,
    // not assumed — `isFromCache: true`, zero logs, zero metrics.
    //
    // That is defensible for tracing, where there is no network time to report.
    // It is a genuine gap for the other two: the fastest requests are missing
    // from the latency figures, and the cache's own hit rate is invisible from
    // the observability this package ships. Moving them above the cache would
    // trade that for a worse defect — a metric recorded and never completed,
    // and a span never closed — so the reporting goes through
    // `CacheConfig.onCacheHit` instead, which fires where the hit is actually
    // served.
    if (tracingConfig != null) {
      dio.interceptors.add(TracingInterceptor(config: tracingConfig));
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
