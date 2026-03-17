import 'cache_storage.dart';

/// Cache strategy options.
enum CacheStrategy {
  /// Return cached data first, then update from network.
  cacheFirst,

  /// Try network first, fallback to cache on failure.
  networkFirst,

  /// Respect HTTP cache headers (Cache-Control, ETag, etc).
  httpCacheAware,

  /// Always use network, never cache.
  networkOnly,

  /// Always use cache if available, never network.
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
