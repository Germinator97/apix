import 'cache_storage.dart';

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

  /// Creates a [CacheConfig] with the given parameters.
  CacheConfig({
    CacheStorage? storage,
    this.strategy = CacheStrategy.networkFirst,
    this.defaultTtl = const Duration(minutes: 5),
    this.cacheErrors = false,
    this.cacheableMethods = const ['GET'],
    this.enableDeduplication = true,
    this.deduplicateMethods = const ['GET'],
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
  }) {
    return CacheConfig(
      storage: storage ?? this.storage,
      strategy: strategy ?? this.strategy,
      defaultTtl: defaultTtl ?? this.defaultTtl,
      cacheErrors: cacheErrors ?? this.cacheErrors,
      cacheableMethods: cacheableMethods ?? this.cacheableMethods,
      enableDeduplication: enableDeduplication ?? this.enableDeduplication,
      deduplicateMethods: deduplicateMethods ?? this.deduplicateMethods,
    );
  }

  @override
  String toString() {
    return 'CacheConfig(strategy: $strategy, '
        'defaultTtl: $defaultTtl, '
        'cacheErrors: $cacheErrors, '
        'cacheableMethods: $cacheableMethods, '
        'enableDeduplication: $enableDeduplication)';
  }
}
