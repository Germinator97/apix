import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../errors/api_exception.dart';
import '../http/cache_vary.dart';
import 'cache_config.dart';
import 'cache_entry.dart';
import 'cache_storage.dart';
import 'request_deduplicator.dart';

/// Interceptor that provides response caching with configurable strategies.
///
/// Supports multiple caching strategies:
/// - [CacheStrategy.cacheFirst]: serve cache immediately — stale included —
///   and revalidate in the background
/// - [CacheStrategy.networkFirst]: try network first, fall back to cache
///   (possibly stale) on failure
/// - [CacheStrategy.httpCacheAware]: follow the server's `Cache-Control` /
///   `ETag` directives
/// - [CacheStrategy.cacheOnly]: only use cache, and only while it is valid
/// - [CacheStrategy.networkOnly]: always use network, never read cache
///
/// The TTL is enforced here, not by the [CacheStorage]: a backend only stores
/// and returns. See [CacheStorage.get].
///
/// Whenever a cached body is handed back, `Response.extra` carries
/// [fromCacheKey], plus [fromCacheStaleKey] when that body had expired — read
/// them through `response.isFromCache` / `response.isStale`.
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

  /// The request deduplicator for concurrent requests.
  ///
  /// Scoped by the same [CacheConfig.varyHeaders] as the cache: collapsing two
  /// concurrent requests from different callers hands the second one a body it
  /// never asked for, exactly as a shared cache entry would.
  late final RequestDeduplicator _deduplicator =
      RequestDeduplicator(varyHeaders: config.varyHeaders);

  /// Dio instance for executing deduplicated requests.
  Dio? _dio;

  /// Creates a [CacheInterceptor] with the given [config].
  CacheInterceptor({required this.config});

  /// Sets the Dio instance for deduplication.
  /// Must be called after adding this interceptor to Dio.
  void setDio(Dio dio) {
    _dio = dio;
  }

  /// Returns the request deduplicator (for testing).
  RequestDeduplicator get deduplicator => _deduplicator;

  // ==================== Cache Invalidation API ====================

  /// Invalidates a specific cache entry by its exact key.
  ///
  /// Returns true if the entry existed and was removed.
  Future<bool> invalidate(String key) async {
    final existed = await config.storage.has(key);
    if (existed) {
      await config.storage.remove(key);
    }
    return existed;
  }

  /// Invalidates all cache entries for a specific URL and method.
  ///
  /// Accepts both relative paths and absolute URLs.
  /// Relative paths are resolved against the client's base URL.
  /// All query parameter variants for the same URL are invalidated.
  ///
  /// Returns true if at least one entry was removed.
  ///
  /// Example:
  /// ```dart
  /// await interceptor.invalidateUrl('/users/123', method: 'GET');
  /// ```
  Future<bool> invalidateUrl(String url, {String method = 'GET'}) async {
    final resolvedUrl = _resolveUrl(url);
    final prefix = '$method:$resolvedUrl';
    final removed = await config.storage.removeWhere(
      (key) => key.startsWith(prefix),
    );
    return removed > 0;
  }

  /// Resolves a relative URL against the client's base URL.
  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    if (_dio != null) {
      final baseUrl = _dio!.options.baseUrl;
      return '$baseUrl$url';
    }
    return url;
  }

  /// Invalidates all cache entries matching a predicate.
  ///
  /// Returns the number of entries removed.
  ///
  /// Example:
  /// ```dart
  /// // Remove all user-related cache entries
  /// await interceptor.invalidateWhere((key) => key.contains('/users'));
  /// ```
  Future<int> invalidateWhere(bool Function(String key) predicate) async {
    return config.storage.removeWhere(predicate);
  }

  /// Invalidates all cache entries whose keys start with the given prefix.
  ///
  /// Returns the number of entries removed.
  ///
  /// Example:
  /// ```dart
  /// // Remove all GET requests to a specific endpoint
  /// await interceptor.invalidateByPrefix('GET:https://api.com/users');
  /// ```
  Future<int> invalidateByPrefix(String prefix) async {
    return config.storage.removeByPrefix(prefix);
  }

  /// Invalidates all cache entries for a specific path pattern.
  ///
  /// The pattern matches against the URL path portion.
  /// Returns the number of entries removed.
  ///
  /// Example:
  /// ```dart
  /// // Remove all cache for /users/* endpoints
  /// await interceptor.invalidatePath('/users');
  /// ```
  Future<int> invalidatePath(String pathPattern) async {
    return config.storage.removeWhere((key) => key.contains(pathPattern));
  }

  /// Clears all cached entries.
  ///
  /// Returns the number of entries removed.
  Future<int> clearCache() async {
    final allKeys = await config.storage.keys();
    final count = allKeys.length;
    await config.storage.clear();
    return count;
  }

  /// Returns all current cache keys.
  Future<List<String>> getCacheKeys() async {
    return config.storage.keys();
  }

  /// Returns true if a cache entry exists for the given key.
  Future<bool> hasCache(String key) async {
    return config.storage.has(key);
  }

  // ==================== Interceptor Methods ====================

  /// Key used in [RequestOptions.extra] to bypass cache interceptor.
  ///
  /// Used by deduplicated requests to avoid re-entering the cache logic
  /// while still going through auth, logging, and other interceptors.
  static const String _skipCacheKey = '_apix_skip_cache';

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      // Skip cache for deduplicated sub-requests (avoids recursion)
      if (options.extra[_skipCacheKey] == true) {
        handler.next(options);
        return;
      }

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
          options.extra['_cacheKey'] = cacheKey;
          // Check for deduplication
          if (config.shouldDeduplicate(options.method) && _dio != null) {
            await _handleWithDeduplication(
                options, handler, cacheKey, strategy);
          } else {
            handler.next(options);
          }
      }
    } catch (e) {
      // On storage or other failure, fall through to network
      handler.next(options);
    }
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      final options = response.requestOptions;

      // Skip for deduplicated sub-requests (caching handled by the deduplicator)
      if (options.extra[_skipCacheKey] == true) {
        handler.next(response);
        return;
      }

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
      if (_shouldStore(strategy) && _shouldCacheResponse(response)) {
        await _cacheResponse(cacheKey, response, strategy: strategy);
      }

      handler.next(response);
    } catch (_) {
      // On storage failure, pass through the response unmodified
      handler.next(response);
    }
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
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

      // Try to return cached response on network failure. An expired entry is
      // served on purpose here — stale data beats no data when the network is
      // gone — but it is flagged so the caller can say so.
      final cached = await config.storage.get(cacheKey);
      if (cached != null) {
        final response = _buildResponseFromCache(
          options,
          cached,
          stale: cached.isExpired,
        );
        handler.resolve(response);
        return;
      }

      handler.next(err);
    } catch (_) {
      // On storage failure, propagate the original error
      handler.next(err);
    }
  }

  /// Handles CacheFirst strategy: serve the cache immediately, refresh behind.
  ///
  /// The caller never waits on the network when an entry exists — including an
  /// expired one, which is served with `isStale` set while a background
  /// revalidation updates the entry. This is stale-while-revalidate, and it is
  /// what `cacheFirst` has always claimed to do.
  ///
  /// Network volume is unchanged compared with blocking on expiry: a fresh
  /// entry still triggers nothing, a stale one still triggers exactly one
  /// request. Only the waiting disappears.
  Future<void> _handleCacheFirst(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String cacheKey,
  ) async {
    final cached = await config.storage.get(cacheKey);

    if (cached != null) {
      if (cached.isValid) {
        handler.resolve(_buildResponseFromCache(options, cached));
        return;
      }

      // Stale: serve it now, revalidate behind. If no Dio is wired (setDio was
      // never called) there is nothing to revalidate with, so fall through to
      // a normal blocking request rather than serving stale data forever.
      if (_dio != null) {
        handler.resolve(
          _buildResponseFromCache(options, cached, stale: true),
        );
        _revalidateInBackground(options, cacheKey);
        return;
      }
    }

    // No cache, proceed with network request
    options.extra['_cacheKey'] = cacheKey;
    handler.next(options);
  }

  /// Refreshes [cacheKey] out of band, after a stale entry was already served.
  ///
  /// Nothing awaits this. Every failure is swallowed on purpose: the caller
  /// already holds a usable response, and an unhandled asynchronous error
  /// would surface as a zone-level crash with no request to attach it to. The
  /// stale entry simply survives until the next attempt.
  void _revalidateInBackground(RequestOptions options, String cacheKey) {
    unawaited(() async {
      try {
        final response = await _executeRequest(options);
        if (_shouldCacheResponse(response)) {
          await _cacheResponse(
            cacheKey,
            response,
            strategy: CacheStrategy.cacheFirst,
          );
        }
      } catch (_) {
        // Offline, server error, storage failure: keep the stale entry.
      }
    }());
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

  /// Handles CacheOnly strategy: return a valid cache entry, or fail.
  ///
  /// Never serves an expired entry: this strategy has no network to fall back
  /// on, so honouring the TTL is the only thing keeping `defaultTtl` meaningful
  /// here.
  Future<void> _handleCacheOnly(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String cacheKey,
  ) async {
    final cached = await config.storage.get(cacheKey);

    if (cached != null && cached.isValid) {
      final response = _buildResponseFromCache(options, cached);
      handler.resolve(response);
      return;
    }

    // No usable cache available, reject
    handler.reject(
      DioException(
        requestOptions: options,
        error: CacheException(
          cached == null
              ? 'No cached response available'
              : 'Cached response has expired',
        ),
        type: DioExceptionType.unknown,
      ),
    );
  }

  /// Handles request with deduplication.
  Future<void> _handleWithDeduplication(
    RequestOptions options,
    RequestInterceptorHandler handler,
    String cacheKey,
    CacheStrategy strategy,
  ) async {
    try {
      final response = await _deduplicator.deduplicate(
        options,
        () => _executeRequest(options),
      );

      // Cache the response if needed
      if (_shouldStore(strategy) && _shouldCacheResponse(response)) {
        await _cacheResponse(cacheKey, response, strategy: strategy);
      }

      handler.resolve(response);
    } on DioException catch (e) {
      // For networkFirst, try cache fallback
      if (strategy == CacheStrategy.networkFirst) {
        final cached = await config.storage.get(cacheKey);
        if (cached != null) {
          final cachedResponse = _buildResponseFromCache(
            options,
            cached,
            stale: cached.isExpired,
          );
          handler.resolve(cachedResponse);
          return;
        }
      }
      handler.reject(e);
    }
  }

  /// Executes the actual network request using the main Dio instance.
  ///
  /// Marks the request with [_skipCacheKey] to bypass this interceptor
  /// on re-entry, while preserving auth, logging, and other interceptors.
  Future<Response<dynamic>> _executeRequest(RequestOptions options) async {
    return _dio!.fetch<dynamic>(options.copyWith(
      extra: {...options.extra, _skipCacheKey: true},
    ));
  }

  /// Generates a cache key from request options.
  ///
  /// Uses method + base URL path (without query) + sorted query params, then
  /// the identity fragment from [CacheConfig.varyHeaders], to produce
  /// deterministic keys that cannot be shared across callers.
  ///
  /// Without that last part the key described only *what* was asked, never
  /// *who* asked. Two accounts on one device therefore shared every entry:
  /// after a logout and a login, `GET /me` returned the previous account's
  /// body — persisted across restarts by `FileCacheStorage`, and never
  /// cleared, since the documented logout only dropped the tokens.
  String _generateCacheKey(RequestOptions options) {
    final uri = options.uri;
    final buffer = StringBuffer()
      ..write(options.method)
      ..write(':')
      ..write('${uri.scheme}://${uri.authority}${uri.path}');

    // Read the query off `uri`, never off `options.queryParameters`.
    //
    // dio merges both sources into `uri`: parameters passed as
    // `queryParameters:` *and* those the caller wrote straight into the path.
    // Reading only the map dropped the second kind entirely, so
    // `get('/users?page=1')` and `get('/users?page=2')` produced the same key
    // and the second call was served the first one's body — one network
    // request for two different pages. The same two pages passed as
    // `queryParameters: {'page': n}` did not collide, so whether the defect
    // fired depended on how the caller happened to spell the request.
    //
    // Sorted by name so declaration order is irrelevant; repeated values keep
    // their order, which can carry meaning.
    final params = uri.queryParametersAll;
    if (params.isNotEmpty) {
      final names = params.keys.toList()..sort();
      final canonical =
          names.map((name) => '$name=${params[name]!.join(',')}').join('&');
      buffer.write('?$canonical');
    }

    // Digest, never the value: `EncryptedCacheStorage` leaves keys in clear
    // text on purpose, so an embedded bearer token would be written to disk by
    // the very storage picked for sensitive data.
    final vary = varyFingerprint(options, config.varyHeaders);
    if (vary != null) buffer.write('|v:$vary');

    return buffer.toString();
  }

  /// Gets the cache strategy for this request.
  CacheStrategy _getStrategy(RequestOptions options) {
    // Allow per-request strategy override
    final override = options.extra['cacheStrategy'] as CacheStrategy?;
    return override ?? config.strategy;
  }

  /// Whether [strategy] is allowed to *write* to the store at all.
  ///
  /// [CacheStrategy.networkOnly] documents itself as "always use network, never
  /// read cache" — and only the reading half was ever enforced. Every response
  /// was still written, so choosing `networkOnly` on a wallet moved balances,
  /// transactions and entitlements through a store nobody ever read from. The
  /// only escape was a `CacheStorage` whose writes were deliberately dropped.
  ///
  /// A strategy that never reads has nothing to gain from writing: the entry it
  /// leaves behind cannot serve a later request under the same strategy, and
  /// `onError` explicitly refuses to fall back for it.
  bool _shouldStore(CacheStrategy strategy) =>
      strategy != CacheStrategy.networkOnly;

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
    CacheEntry entry, {
    bool stale = false,
  }) {
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
      extra: {fromCacheKey: true, fromCacheStaleKey: stale},
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
class CacheException extends ApiException {
  /// Creates a [CacheException] with the given [message].
  const CacheException(String message) : super(message: message);

  @override
  String toString() => 'CacheException: $message';
}

/// Key set on `Response.extra` when the body came from the cache.
const String fromCacheKey = 'fromCache';

/// Key set on `Response.extra` when the cached body served had expired.
const String fromCacheStaleKey = 'fromCacheStale';

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
}

/// Provenance of a response: cache or network, fresh or stale.
extension CacheResponseExtension on Response<dynamic> {
  /// Whether this body was served from the cache rather than the network.
  bool get isFromCache => extra[fromCacheKey] == true;

  /// Whether this body was served from the cache **past its TTL**.
  ///
  /// True in the two situations where apix knowingly hands back expired data:
  /// `cacheFirst` serving instantly while it revalidates behind, and
  /// `networkFirst` / `httpCacheAware` falling back to cache after a network
  /// failure. Both are useful; both are lies if the caller can't tell.
  ///
  /// Surface it — "showing data from earlier, refreshing…" — anywhere the
  /// value's age changes what the user should do with it. On an amount, a
  /// balance or a status, treat it as mandatory.
  ///
  /// Always false for a network response.
  bool get isStale => extra[fromCacheStaleKey] == true;
}
