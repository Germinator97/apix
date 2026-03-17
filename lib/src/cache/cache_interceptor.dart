import 'dart:convert';

import 'package:dio/dio.dart';

import 'cache_config.dart';
import 'cache_entry.dart';

/// Interceptor that provides response caching with configurable strategies.
///
/// Supports multiple caching strategies:
/// - [CacheStrategy.cacheFirst]: Return cache if available, otherwise network
/// - [CacheStrategy.networkFirst]: Try network first, fallback to cache
/// - [CacheStrategy.cacheOnly]: Only use cache, fail if not available
/// - [CacheStrategy.networkOnly]: Always use network, never cache
///
/// Example:
/// ```dart
/// final cacheInterceptor = CacheInterceptor(
///   config: CacheConfig(
///     strategy: CacheStrategy.networkFirst,
///     defaultTtl: Duration(minutes: 5),
///   ),
/// );
/// dio.interceptors.add(cacheInterceptor);
/// ```
class CacheInterceptor extends Interceptor {
  /// The cache configuration.
  final CacheConfig config;

  /// Creates a [CacheInterceptor] with the given [config].
  CacheInterceptor({required this.config});

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Only cache configured methods
    if (!config.shouldCache(options.method)) {
      handler.next(options);
      return;
    }

    final cacheKey = _generateCacheKey(options);
    final strategy = _getStrategy(options);

    switch (strategy) {
      case CacheStrategy.cacheFirst:
        await _handleCacheFirst(options, handler, cacheKey);
      case CacheStrategy.cacheOnly:
        await _handleCacheOnly(options, handler, cacheKey);
      case CacheStrategy.httpCacheAware:
        await _handleHttpCacheAware(options, handler, cacheKey);
      case CacheStrategy.networkFirst:
      case CacheStrategy.networkOnly:
        // Let request proceed, handle in onResponse/onError
        options.extra['_cacheKey'] = cacheKey;
        handler.next(options);
    }
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final options = response.requestOptions;

    // Only cache configured methods
    if (!config.shouldCache(options.method)) {
      handler.next(response);
      return;
    }

    final cacheKey =
        options.extra['_cacheKey'] as String? ?? _generateCacheKey(options);
    final strategy = _getStrategy(options);

    // Handle 304 Not Modified for httpCacheAware
    if (strategy == CacheStrategy.httpCacheAware &&
        response.statusCode == 304) {
      final cached = await config.storage.get(cacheKey);
      if (cached != null) {
        final cachedResponse = _buildResponseFromCache(options, cached);
        handler.resolve(cachedResponse);
        return;
      }
    }

    // Check Cache-Control headers for httpCacheAware
    if (strategy == CacheStrategy.httpCacheAware) {
      final cacheControl = _parseCacheControl(response.headers);
      if (cacheControl.noStore) {
        // Don't cache this response
        handler.next(response);
        return;
      }
    }

    // Cache successful responses
    if (_shouldCacheResponse(response)) {
      await _cacheResponse(cacheKey, response, strategy: strategy);
    }

    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final strategy = _getStrategy(options);

    // Only handle networkFirst and httpCacheAware fallback
    if (strategy != CacheStrategy.networkFirst &&
        strategy != CacheStrategy.httpCacheAware) {
      handler.next(err);
      return;
    }

    // Only fallback for cacheable methods
    if (!config.shouldCache(options.method)) {
      handler.next(err);
      return;
    }

    final cacheKey =
        options.extra['_cacheKey'] as String? ?? _generateCacheKey(options);

    // Try to return cached response on network failure
    final cached = await config.storage.get(cacheKey);
    if (cached != null) {
      final response = _buildResponseFromCache(options, cached);
      handler.resolve(response);
      return;
    }

    handler.next(err);
  }

  /// Handles CacheFirst strategy: return cache if available.
  Future<void> _handleCacheFirst(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String cacheKey,
  ) async {
    final cached = await config.storage.get(cacheKey);

    if (cached != null) {
      final response = _buildResponseFromCache(options, cached);
      handler.resolve(response);
      return;
    }

    // No cache, proceed with network request
    options.extra['_cacheKey'] = cacheKey;
    handler.next(options);
  }

  /// Handles HttpCacheAware strategy: add conditional headers if cached.
  Future<void> _handleHttpCacheAware(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String cacheKey,
  ) async {
    final cached = await config.storage.get(cacheKey);

    if (cached != null) {
      // Add If-None-Match header if we have an ETag
      if (cached.etag != null) {
        options.headers['If-None-Match'] = cached.etag;
      }

      // Check if cache is still fresh (no need to revalidate)
      if (cached.isValid) {
        // Check if we should revalidate based on no-cache
        final shouldRevalidate = options.extra['_forceRevalidate'] == true;
        if (!shouldRevalidate) {
          final response = _buildResponseFromCache(options, cached);
          handler.resolve(response);
          return;
        }
      }
    }

    options.extra['_cacheKey'] = cacheKey;
    handler.next(options);
  }

  /// Handles CacheOnly strategy: return cache or fail.
  Future<void> _handleCacheOnly(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String cacheKey,
  ) async {
    final cached = await config.storage.get(cacheKey);

    if (cached != null) {
      final response = _buildResponseFromCache(options, cached);
      handler.resolve(response);
      return;
    }

    // No cache available, reject
    handler.reject(
      DioException(
        requestOptions: options,
        error: const CacheException('No cached response available'),
        type: DioExceptionType.unknown,
      ),
    );
  }

  /// Generates a cache key from request options.
  String _generateCacheKey(RequestOptions options) {
    final buffer = StringBuffer()
      ..write(options.method)
      ..write(':')
      ..write(options.uri.toString());

    // Include query parameters in key
    if (options.queryParameters.isNotEmpty) {
      final sortedParams = Map.fromEntries(
        options.queryParameters.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      );
      buffer.write(
          '?${Uri(queryParameters: _stringifyParams(sortedParams)).query}');
    }

    return buffer.toString();
  }

  /// Converts query parameters to string map.
  Map<String, String> _stringifyParams(Map<String, dynamic> params) {
    return params.map((key, value) => MapEntry(key, value.toString()));
  }

  /// Gets the cache strategy for this request.
  CacheStrategy _getStrategy(RequestOptions options) {
    // Allow per-request strategy override
    final override = options.extra['cacheStrategy'] as CacheStrategy?;
    return override ?? config.strategy;
  }

  /// Returns true if the response should be cached.
  bool _shouldCacheResponse(Response<dynamic> response) {
    final statusCode = response.statusCode ?? 0;

    // Cache successful responses
    if (statusCode >= 200 && statusCode < 300) {
      return true;
    }

    // Optionally cache error responses
    if (config.cacheErrors && statusCode >= 400) {
      return true;
    }

    return false;
  }

  /// Caches a response.
  Future<void> _cacheResponse(
    String key,
    Response<dynamic> response, {
    CacheStrategy? strategy,
  }) async {
    final data = response.data;
    final jsonString = data is String ? data : jsonEncode(data);

    // Determine TTL based on Cache-Control for httpCacheAware
    Duration ttl = config.defaultTtl;
    String? etag;

    if (strategy == CacheStrategy.httpCacheAware) {
      final cacheControl = _parseCacheControl(response.headers);
      if (cacheControl.maxAge != null) {
        ttl = Duration(seconds: cacheControl.maxAge!);
      }
      etag = _getEtag(response.headers);
    }

    final entry = CacheEntry.withTtl(
      data: jsonString,
      statusCode: response.statusCode ?? 200,
      ttl: ttl,
      etag: etag,
      headers: response.headers.map.map(
        (key, value) => MapEntry(key, value.join(', ')),
      ),
    );

    await config.storage.set(key, entry);
  }

  /// Parses Cache-Control header into structured data.
  CacheControlHeader _parseCacheControl(Headers headers) {
    final headerValue = headers.value('cache-control');
    if (headerValue == null) {
      return const CacheControlHeader();
    }

    final directives =
        headerValue.split(',').map((s) => s.trim().toLowerCase());
    int? maxAge;
    bool noCache = false;
    bool noStore = false;
    bool mustRevalidate = false;

    for (final directive in directives) {
      if (directive.startsWith('max-age=')) {
        final value = directive.substring(8);
        maxAge = int.tryParse(value);
      } else if (directive == 'no-cache') {
        noCache = true;
      } else if (directive == 'no-store') {
        noStore = true;
      } else if (directive == 'must-revalidate') {
        mustRevalidate = true;
      }
    }

    return CacheControlHeader(
      maxAge: maxAge,
      noCache: noCache,
      noStore: noStore,
      mustRevalidate: mustRevalidate,
    );
  }

  /// Gets ETag from response headers.
  String? _getEtag(Headers headers) {
    return headers.value('etag');
  }

  /// Builds a response from a cached entry.
  Response<dynamic> _buildResponseFromCache(
    RequestOptions options,
    CacheEntry entry,
  ) {
    dynamic data;
    try {
      data = jsonDecode(entry.data);
    } catch (_) {
      data = entry.data;
    }

    return Response<dynamic>(
      requestOptions: options,
      data: data,
      statusCode: entry.statusCode,
      headers: Headers.fromMap(
        entry.headers?.map((k, v) => MapEntry(k, [v])) ?? {},
      ),
      extra: {'fromCache': true},
    );
  }
}

/// Parsed Cache-Control header directives.
class CacheControlHeader {
  /// Maximum age in seconds before the response is considered stale.
  final int? maxAge;

  /// If true, the response must be revalidated with the server.
  final bool noCache;

  /// If true, the response must not be stored.
  final bool noStore;

  /// If true, stale responses must be revalidated.
  final bool mustRevalidate;

  /// Creates a [CacheControlHeader] with the given directives.
  const CacheControlHeader({
    this.maxAge,
    this.noCache = false,
    this.noStore = false,
    this.mustRevalidate = false,
  });

  @override
  String toString() {
    return 'CacheControlHeader(maxAge: $maxAge, noCache: $noCache, '
        'noStore: $noStore, mustRevalidate: $mustRevalidate)';
  }
}

/// Exception thrown when cache operations fail.
class CacheException implements Exception {
  /// The error message.
  final String message;

  /// Creates a [CacheException] with the given [message].
  const CacheException(this.message);

  @override
  String toString() => 'CacheException: $message';
}

/// Extension for per-request cache control.
extension CacheRequestExtension on RequestOptions {
  /// Sets a custom cache strategy for this request.
  void setCacheStrategy(CacheStrategy strategy) {
    extra['cacheStrategy'] = strategy;
  }

  /// Disables caching for this request.
  void noCache() {
    extra['cacheStrategy'] = CacheStrategy.networkOnly;
  }

  /// Returns true if this response was served from cache.
  static bool isFromCache(Response<dynamic> response) {
    return response.extra['fromCache'] == true;
  }
}
