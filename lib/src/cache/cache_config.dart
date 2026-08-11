import 'cache_storage.dart';

/// A response served from storage rather than from the network.
///
/// Handed to [CacheConfig.onCacheHit], which exists because nothing else in
/// apix can report one. A hit is resolved from `onRequest`, which ends the
/// chain before the logger, the metrics and the tracing interceptor are
/// reached — deliberately, since a cached response spent no time on the
/// network and a span opened for it would never be closed. The cost of that
/// choice is that the *fastest* requests are the ones missing from every
/// dashboard, and that the cache's own hit rate is invisible from the
/// observability the package provides. This closes it without moving anything
/// in the chain.
class CacheHit {
  /// The storage key the body came from.
  final String key;

  /// The HTTP method of the request that was answered.
  final String method;

  /// The URI of the request that was answered.
  final Uri uri;

  /// Whether the body handed back was past its TTL.
  ///
  /// True in the two situations apix knowingly serves expired data:
  /// `cacheFirst` answering instantly while it revalidates behind, and the
  /// offline fallback of `networkFirst` / `httpCacheAware`. A hit rate that
  /// counts these together with fresh ones is measuring two different things.
  final bool isStale;

  /// The status code stored with the entry.
  final int statusCode;

  /// Creates a [CacheHit].
  const CacheHit({
    required this.key,
    required this.method,
    required this.uri,
    required this.isStale,
    required this.statusCode,
  });

  @override
  String toString() =>
      'CacheHit($method ${uri.path}${isStale ? ' stale' : ''} [$statusCode])';
}

/// Signature for [CacheConfig.onCacheHit].
typedef CacheHitHandler = void Function(CacheHit hit);

/// Cache strategy options.
///
/// Only [cacheFirst] and [networkFirst] can hand back data that is past its
/// TTL; both flag it with `response.isStale`.
enum CacheStrategy {
  /// Serve the cache immediately, then update from the network
  /// (stale-while-revalidate).
  ///
  /// A valid entry is returned as-is and costs no request. An **expired** one
  /// is returned too — flagged `isStale` — while a single background request
  /// refreshes it. The caller never waits on the network when an entry exists.
  ///
  /// Network volume is the same as blocking on expiry would be; only the
  /// waiting disappears. In exchange, the body may be older than [
  /// CacheConfig.defaultTtl]: where that is unacceptable — an amount, a
  /// balance, an authorisation — use [networkFirst], or surface `isStale` in
  /// the UI.
  cacheFirst,

  /// Try network first, fall back to cache on failure.
  ///
  /// The fallback serves whatever is cached, expired included, because stale
  /// data beats no data when the network is gone; it is flagged `isStale` when
  /// so. This is the strategy to pick when freshness matters, since the cache
  /// is only ever consulted after the network has failed.
  networkFirst,

  /// Respect HTTP cache headers (Cache-Control, ETag, etc).
  ///
  /// Freshness is the server's call: a `304 Not Modified` serves the cached
  /// body as fresh regardless of the local TTL.
  httpCacheAware,

  /// Always use network, never read or serve the cache.
  networkOnly,

  /// Serve the cache or fail — never any network.
  ///
  /// Never returns an expired entry: with no network to fall back on,
  /// honouring [CacheConfig.defaultTtl] is the only thing that keeps it
  /// meaningful. A miss and an expiry both raise `CacheException`.
  cacheOnly,
}

/// Configuration for cache behavior.
///
/// Example:
/// ```dart
/// final config = CacheConfig(
///   storage: InMemoryCacheStorage(),
///   strategy: CacheStrategy.networkFirst,
///   defaultTtl: Duration(minutes: 5),
/// );
/// ```
class CacheConfig {
  /// The storage backend for cached responses.
  final CacheStorage storage;

  /// The default caching strategy.
  final CacheStrategy strategy;

  /// Default time-to-live for cached entries.
  final Duration defaultTtl;

  /// Whether to cache error responses.
  final bool cacheErrors;

  /// HTTP methods that should be cached.
  final List<String> cacheableMethods;

  /// Whether to deduplicate identical concurrent requests.
  final bool enableDeduplication;

  /// HTTP methods that should be deduplicated.
  final List<String> deduplicateMethods;

  /// Request headers whose value scopes a cache entry to whoever sent it.
  ///
  /// **Defaults to `['Authorization']`, and that default is load-bearing.**
  /// Without it the cache key is `method + url + query` and nothing else, so
  /// two different users on the same device share every entry: log out, log
  /// back in as someone else, and `GET /me` is served the previous account's
  /// body. With `FileCacheStorage` that survives process restarts, so the leak
  /// outlives the session that created it.
  ///
  /// Values are never stored — only a truncated digest of them reaches the key
  /// (see `varyFingerprint`), because cache keys are deliberately left in clear
  /// text even by `EncryptedCacheStorage`.
  ///
  /// Set to `const []` to opt out and restore the pre-5.0 key. Do that only
  /// where responses genuinely do not depend on the caller — a public price
  /// list, a static catalogue.
  ///
  /// ## Two consequences worth knowing
  ///
  /// A **token refresh changes the fingerprint**, so entries cached under the
  /// old access token stop being hit. That is a cache miss, never a wrong
  /// answer. Where it matters, vary on a header carrying a stable identity
  /// (`['X-User-Id']`) instead of the bearer token.
  ///
  /// The header must already be **on the request** when the cache reads it.
  /// `ApiClientFactory` installs `AuthInterceptor` before `CacheInterceptor`
  /// precisely so it is. Wiring the cache by hand *before* auth would scope
  /// nothing — and scoping nothing looks exactly like working.
  final List<String> varyHeaders;

  /// Called each time a response is answered from storage.
  ///
  /// The only way to see a cache hit from outside the cache. `LoggerConfig`,
  /// `MetricsConfig` and `TracingConfig` never observe one — see [CacheHit] for
  /// why, and why moving them in the chain would be worse.
  ///
  /// Guarded like every other consumer callback: a handler that throws cannot
  /// fail the request it was only meant to watch.
  ///
  /// ```dart
  /// cacheConfig: CacheConfig(
  ///   onCacheHit: (hit) => metrics.increment(
  ///     hit.isStale ? 'cache.stale' : 'cache.fresh',
  ///   ),
  /// )
  /// ```
  final CacheHitHandler? onCacheHit;

  /// Creates a [CacheConfig] with the given parameters.
  CacheConfig({
    CacheStorage? storage,
    this.strategy = CacheStrategy.networkFirst,
    this.defaultTtl = const Duration(minutes: 5),
    this.cacheErrors = false,
    this.cacheableMethods = const ['GET'],
    this.enableDeduplication = true,
    this.deduplicateMethods = const ['GET'],
    this.varyHeaders = const ['Authorization'],
    this.onCacheHit,
  }) : storage = storage ?? InMemoryCacheStorage();

  /// Returns true if the given HTTP method should be cached.
  bool shouldCache(String method) =>
      cacheableMethods.contains(method.toUpperCase());

  /// Returns true if the given HTTP method should be deduplicated.
  bool shouldDeduplicate(String method) =>
      enableDeduplication && deduplicateMethods.contains(method.toUpperCase());

  /// Creates a copy with updated fields.
  CacheConfig copyWith({
    CacheStorage? storage,
    CacheStrategy? strategy,
    Duration? defaultTtl,
    bool? cacheErrors,
    List<String>? cacheableMethods,
    bool? enableDeduplication,
    List<String>? deduplicateMethods,
    List<String>? varyHeaders,
    CacheHitHandler? onCacheHit,
  }) {
    return CacheConfig(
      storage: storage ?? this.storage,
      strategy: strategy ?? this.strategy,
      defaultTtl: defaultTtl ?? this.defaultTtl,
      cacheErrors: cacheErrors ?? this.cacheErrors,
      cacheableMethods: cacheableMethods ?? this.cacheableMethods,
      enableDeduplication: enableDeduplication ?? this.enableDeduplication,
      deduplicateMethods: deduplicateMethods ?? this.deduplicateMethods,
      varyHeaders: varyHeaders ?? this.varyHeaders,
      onCacheHit: onCacheHit ?? this.onCacheHit,
    );
  }

  @override
  String toString() {
    return 'CacheConfig(strategy: $strategy, '
        'defaultTtl: $defaultTtl, '
        'cacheErrors: $cacheErrors, '
        'cacheableMethods: $cacheableMethods, '
        'enableDeduplication: $enableDeduplication, '
        'varyHeaders: $varyHeaders)';
  }
}
