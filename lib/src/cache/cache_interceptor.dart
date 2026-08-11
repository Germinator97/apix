import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../client/response_validator_interceptor.dart';
import '../errors/api_exception.dart';
import '../http/body_fingerprint.dart';
import '../http/cache_vary.dart';
import '../observability/observer_guard.dart';
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
  /// All query parameter variants — and all callers, when
  /// [CacheConfig.varyHeaders] is in play — are invalidated for that exact URL.
  ///
  /// **Sibling paths are not touched.** The match stops at the URL boundary, so
  /// `invalidateUrl('/users')` leaves `/users-archived` and `/users/123` alone.
  /// It used to be a bare prefix match, which swept both away — a surprise
  /// nobody could see, since a cache entry that vanished early just looks like
  /// a miss. Reach for [invalidatePath] or [invalidateByPrefix] when clearing a
  /// whole subtree really is the intent.
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
      (key) => _matchesUrlExactly(key, prefix),
    );
    return removed > 0;
  }

  /// Whether [key] is an entry for exactly [prefix], rather than for a URL that
  /// merely starts with it.
  ///
  /// A key is `METHOD:scheme://authority/path` optionally followed by `?query`
  /// and by the `|v:` identity fragment, so anything else after the prefix
  /// means a different URL.
  bool _matchesUrlExactly(String key, String prefix) {
    if (!key.startsWith(prefix)) return false;
    if (key.length == prefix.length) return true;
    final next = key[prefix.length];
    return next == '?' || next == '|';
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
  /// Returns the number of entries removed — expired ones included, which it
  /// used to under-report because [CacheStorage.keys] swept them on its way
  /// past.
  Future<int> clearCache() async {
    final allKeys = await config.storage.keys();
    final count = allKeys.length;
    await config.storage.clear();
    return count;
  }

  /// Returns all current cache keys, expired entries included.
  ///
  /// **Reading no longer deletes.** This used to purge every expired entry it
  /// walked over, so asking what was cached destroyed the offline fallback —
  /// an expired entry is precisely what `networkFirst` serves when the network
  /// is gone. Reach for [evictExpired] when removing them is the intent.
  Future<List<String>> getCacheKeys() async {
    return config.storage.keys();
  }

  /// Removes every entry that is past its TTL, and returns how many went.
  ///
  /// The deletion that [getCacheKeys] used to perform as a side effect, under
  /// a name that says so. Worth calling on a memory-pressure signal or at
  /// logout; not worth calling routinely, since `FileCacheStorage` already
  /// bounds itself by count and an expired entry still has value offline.
  ///
  /// Works against any [CacheStorage], including a consumer's own: it reads
  /// through the interface rather than requiring a method of its own.
  Future<int> evictExpired() async {
    var removed = 0;
    for (final key in await config.storage.keys()) {
      final entry = await config.storage.get(key);
      if (entry != null && entry.isExpired) {
        await config.storage.remove(key);
        removed++;
      }
    }
    return removed;
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
    } catch (e, st) {
      // On storage or other failure, fall through to network — and say so.
      _reportCacheFailure(CacheOperation.read, e, st);
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

      // Handle 304 Not Modified for httpCacheAware.
      //
      // Only reachable when the caller widened `validateStatus` to accept a
      // 304; with dio's default it arrives as an error, and `onError` handles
      // it. Both routes go through the same helper so they cannot drift.
      if (strategy == CacheStrategy.httpCacheAware &&
          response.statusCode == 304) {
        final revalidated =
            await _serveRevalidated(options, cacheKey, response);
        if (revalidated != null) {
          handler.resolve(revalidated);
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
    } catch (e, st) {
      // On storage failure, pass through the response unmodified.
      _reportCacheFailure(CacheOperation.write, e, st);
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

      // A body the consumer's `responseValidator` refused is a business
      // failure, not a transport one. Answering it from storage would swap the
      // failure the caller must see for a stale success.
      if (options.extra[ResponseValidatorInterceptor.validationFailedKey] ==
          true) {
        handler.next(err);
        return;
      }

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

      // A 304 is not a failure, it is the successful outcome of a conditional
      // request — but dio's default `validateStatus` accepts only 2xx, so it
      // arrives here as an error. Handling it in `onResponse` alone meant the
      // branch never ran: the 304 fell through to the generic fallback below,
      // which served the entry flagged `isStale` (it had to be expired to be
      // revalidated at all) and left its TTL untouched. So a *successful*
      // revalidation reported stale data and re-hit the network on every later
      // request — `httpCacheAware` degenerated into "always revalidate", the
      // opposite of what it documents.
      if (strategy == CacheStrategy.httpCacheAware &&
          err.response?.statusCode == 304) {
        final revalidated =
            await _serveRevalidated(options, cacheKey, err.response!);
        if (revalidated != null) {
          handler.resolve(revalidated);
          return;
        }
      }

      // Try to return cached response on network failure. An expired entry is
      // served on purpose here — stale data beats no data when the network is
      // gone — but it is flagged so the caller can say so.
      final cached = await config.storage.get(cacheKey);
      if (cached != null) {
        final response = _buildResponseFromCache(
          options,
          cached,
          cacheKey,
          stale: cached.isExpired,
        );
        handler.resolve(response);
        return;
      }

      handler.next(err);
    } catch (e, st) {
      // On storage failure, propagate the original error.
      _reportCacheFailure(CacheOperation.read, e, st);
      handler.next(err);
    }
  }

  /// Answers a `304 Not Modified` from the stored entry, restarting its
  /// lifetime first.
  ///
  /// Returns null when there is nothing stored to confirm, in which case the
  /// caller carries on with its normal handling.
  ///
  /// Restarting the TTL is the whole point: a 304 is the server saying "what
  /// you hold is still current". Serving the body without recording that left
  /// the entry expired, so the next request revalidated again — and the one
  /// after that — while every hit was flagged `isStale`, telling callers the
  /// data was old at the exact moment the server had confirmed it was not.
  ///
  /// The new lifetime comes from the 304's own `Cache-Control` when it carries
  /// one, since that is the server's current answer, not the one it gave when
  /// the body was first stored.
  Future<Response<dynamic>?> _serveRevalidated(
    RequestOptions options,
    String cacheKey,
    Response<dynamic> notModified,
  ) async {
    final cached = await config.storage.get(cacheKey);
    if (cached == null) return null;

    final refreshed = cached.revalidated(
      ttl: _ttlFor(notModified, CacheStrategy.httpCacheAware),
      etag: _getEtag(notModified.headers),
    );
    await config.storage.set(cacheKey, refreshed);

    return _buildResponseFromCache(options, refreshed, cacheKey);
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
        handler.resolve(_buildResponseFromCache(options, cached, cacheKey));
        return;
      }

      // Stale: serve it now, revalidate behind. If no Dio is wired (setDio was
      // never called) there is nothing to revalidate with, so fall through to
      // a normal blocking request rather than serving stale data forever.
      if (_dio != null) {
        handler.resolve(
          _buildResponseFromCache(options, cached, cacheKey, stale: true),
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
        final shouldRevalidate = options.extra[forceRevalidateKey] == true;
        if (!shouldRevalidate) {
          final response = _buildResponseFromCache(options, cached, cacheKey);
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
      final response = _buildResponseFromCache(options, cached, cacheKey);
      handler.resolve(response);
      return;
    }

    // No usable cache available, reject — with `true`, so the failure still
    // travels the rest of the error chain. Without it a `cacheOnly` miss was
    // invisible to logging, metrics and error tracking, and left the metrics
    // in-flight entry for this request dangling.
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
      true,
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

      // Storing is deliberately unable to fail the request.
      //
      // It used to be a bare `await _cacheResponse(...)` sitting *before* the
      // resolve, so a storage failure escaped to `onRequest`'s catch — which
      // falls through to `handler.next(options)` and sends the request a second
      // time. Measured on the default configuration: two network calls, and the
      // caller handed the **second** response. Not merely wasted traffic, a
      // different answer than the one that was actually computed first; and a
      // duplicated side effect for anyone who widened `cacheableMethods`.
      //
      // Kept awaited rather than moved after the resolve: the write stays
      // deterministic for callers that inspect the store right after a request.
      if (_shouldStore(strategy) && _shouldCacheResponse(response)) {
        await _storeQuietly(cacheKey, response, strategy);
      }

      handler.resolve(response);
    } on DioException catch (e) {
      // For networkFirst, try cache fallback. Read through the guarded helper
      // for the same reason: a throwing read here would escape to the same
      // catch and replay the request that has just failed.
      if (strategy == CacheStrategy.networkFirst) {
        final cached = await _readQuietly(cacheKey);
        if (cached != null) {
          final cachedResponse = _buildResponseFromCache(
            options,
            cached,
            cacheKey,
            stale: cached.isExpired,
          );
          handler.resolve(cachedResponse);
          return;
        }
      }
      handler.reject(e);
    }
  }

  /// Writes an entry, absorbing any storage failure.
  ///
  /// Used on the paths where a response is already in hand. There, a storage
  /// exception has nothing to do with the request's outcome, and letting it
  /// travel changes that outcome — see the note in [_handleWithDeduplication].
  Future<void> _storeQuietly(
    String key,
    Response<dynamic> response,
    CacheStrategy? strategy,
  ) async {
    try {
      await _cacheResponse(key, response, strategy: strategy);
    } catch (e, st) {
      // The caller keeps its response; the entry simply is not written — and
      // the consumer is told, which is the part that was missing.
      _reportCacheFailure(CacheOperation.write, e, st, key: key);
    }
  }

  /// Reads an entry, absorbing any storage failure as a miss.
  Future<CacheEntry?> _readQuietly(String key) async {
    try {
      return await config.storage.get(key);
    } catch (e, st) {
      _reportCacheFailure(CacheOperation.read, e, st, key: key);
      return null;
    }
  }

  /// Hands a storage failure to [CacheConfig.onCacheError], if one is wired.
  ///
  /// Absorbing the failure is right: a cache that cannot answer is a cache
  /// miss, and failing the request over it would turn a degraded optimisation
  /// into an outage. Absorbing it *without a word* is what was wrong. A backend
  /// refusing every operation left the client permanently cacheless with no
  /// moment at which anyone could find out — every request still succeeded.
  void _reportCacheFailure(
    CacheOperation operation,
    Object error,
    StackTrace stackTrace, {
    String? key,
  }) {
    final handler = config.onCacheError;
    if (handler == null) return;
    guardObserver(() => handler(CacheFailure(
          operation: operation,
          key: key,
          error: error,
          stackTrace: stackTrace,
        )));
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

    // The body, for the methods that carry one.
    //
    // `cacheableMethods` is a public list and nothing stopped a consumer from
    // adding `POST`. Until this line, the key described the method, the URL and
    // the caller — never *what was asked*. Two searches with different payloads
    // therefore shared one entry: measured, `{"q":"alice"}` and `{"q":"bob"}`
    // collapsed into a single network call and the second caller received the
    // first one's results.
    //
    // Null for a body-less request, so every `GET` keeps the key it has always
    // had and no stored entry is orphaned by this.
    final body = bodyFingerprint(options.data);
    if (body != null) buffer.write('|b:$body');

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
    final (encoded, encoding) = _encodeBody(response.data);

    final entry = CacheEntry.withTtl(
      data: encoded,
      encoding: encoding,
      statusCode: response.statusCode ?? 200,
      ttl: _ttlFor(response, strategy),
      etag: strategy == CacheStrategy.httpCacheAware
          ? _getEtag(response.headers)
          : null,
      headers: response.headers.map.map(
        (key, value) => MapEntry(key, value.join(', ')),
      ),
    );

    await config.storage.set(key, entry);
  }

  /// How long an entry built from [response] should live.
  ///
  /// Under `httpCacheAware` this reads the server's own directives, all three
  /// of which used to be parsed and then ignored except `max-age`:
  ///
  /// - `no-cache` and `must-revalidate` mean "you may keep this, but confirm it
  ///   before using it again". That is a zero lifetime here: the entry stays on
  ///   disk with its `ETag`, and the next request revalidates — cheaply, since
  ///   a `304` costs no body and now correctly restarts the entry.
  /// - `max-age` sets the lifetime.
  ///
  /// Ignoring the first two meant a server marking a resource as
  /// must-revalidate had it served from cache for `defaultTtl` regardless —
  /// apix deciding freshness for a strategy whose entire premise is that the
  /// server decides.
  Duration _ttlFor(Response<dynamic> response, CacheStrategy? strategy) {
    if (strategy != CacheStrategy.httpCacheAware) return config.defaultTtl;
    final cacheControl = _parseCacheControl(response.headers);
    if (cacheControl.noCache || cacheControl.mustRevalidate) {
      return Duration.zero;
    }
    final maxAge = cacheControl.maxAge;
    return maxAge == null ? config.defaultTtl : Duration(seconds: maxAge);
  }

  /// Encodes a response body for storage, recording how, so the hit can hand
  /// back the same runtime type the network handed back.
  ///
  /// Everything used to go through `jsonEncode`/`jsonDecode`, which is not a
  /// round trip for two common bodies: a `text/plain` payload of `12345` came
  /// back as the **int** `12345`, and a `ResponseType.bytes` download came back
  /// as a `List<dynamic>`, so any cast to `Uint8List` at the call site threw —
  /// on the second request only, which is what made it so hard to see.
  (String, CacheBodyEncoding) _encodeBody(dynamic data) {
    if (data == null) return ('', CacheBodyEncoding.empty);
    if (data is String) return (data, CacheBodyEncoding.text);
    if (data is Uint8List || data is List<int>) {
      return (base64Encode(data as List<int>), CacheBodyEncoding.bytes);
    }
    return (jsonEncode(data), CacheBodyEncoding.json);
  }

  /// Reverses [_encodeBody].
  dynamic _decodeBody(CacheEntry entry) {
    switch (entry.encoding) {
      case CacheBodyEncoding.empty:
        return null;
      case CacheBodyEncoding.text:
        return entry.data;
      case CacheBodyEncoding.bytes:
        return base64Decode(entry.data);
      case CacheBodyEncoding.json:
        try {
          return jsonDecode(entry.data);
        } catch (_) {
          // An entry written before `encoding` existed, holding a body that was
          // never JSON. Handing the raw string back is what the old code did.
          return entry.data;
        }
    }
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

  /// Builds a response from a cached entry, and reports the hit.
  ///
  /// Every path that answers from storage passes through here — the five
  /// strategies, the 304 confirmation and both offline fallbacks — which is why
  /// [CacheConfig.onCacheHit] is fired from this one place rather than from
  /// each of them. A reporting call added per site is a reporting call that
  /// will be missing from the next site.
  Response<dynamic> _buildResponseFromCache(
    RequestOptions options,
    CacheEntry entry,
    String cacheKey, {
    bool stale = false,
  }) {
    final handler = config.onCacheHit;
    if (handler != null) {
      guardObserver(() => handler(CacheHit(
            key: cacheKey,
            method: options.method,
            uri: options.uri,
            isStale: stale,
            statusCode: entry.statusCode,
          )));
    }

    return Response<dynamic>(
      requestOptions: options,
      data: _decodeBody(entry),
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

/// Key set on `RequestOptions.extra` to force a conditional revalidation.
const String forceRevalidateKey = '_forceRevalidate';

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

  /// Under [CacheStrategy.httpCacheAware], revalidates with the server even
  /// when the stored entry is still fresh.
  ///
  /// Sends the stored `ETag` as `If-None-Match`, so an unchanged resource costs
  /// a `304` with no body and the entry's lifetime restarts. Use it for a
  /// pull-to-refresh: the user asked for the current answer, and a cheap
  /// confirmation is a better one than a full download.
  ///
  /// The interceptor honoured this flag from the start, but nothing in the
  /// public API ever set it — only a test did, by writing the private key by
  /// hand.
  void forceRevalidate() {
    extra[forceRevalidateKey] = true;
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
