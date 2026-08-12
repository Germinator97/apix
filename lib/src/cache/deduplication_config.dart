/// Configuration for standalone request deduplication.
///
/// Deduplication collapses identical concurrent requests into a single network
/// call, with every caller receiving the same response. That is useful on its
/// own — three widgets asking for the same profile at once should not produce
/// three requests — and it says nothing about whether responses should be
/// *stored*.
///
/// Until this config existed, the only way to get deduplication was to install
/// the cache, because `RequestDeduplicator` was instantiated exclusively by
/// `CacheInterceptor`. On a domain where nothing may be retained — a wallet, a
/// medical record — that forced consumers to supply a `CacheStorage` whose
/// writes were deliberately dropped, just to close a path they never wanted.
///
/// Example:
/// ```dart
/// final client = ApiClientFactory.create(
///   baseUrl: 'https://api.example.com',
///   deduplicationConfig: const DeduplicationConfig(),
///   // no cacheConfig: nothing is ever written to a store
/// );
/// ```
class DeduplicationConfig {
  /// Whether deduplication is active.
  final bool enabled;

  /// HTTP methods eligible for deduplication.
  ///
  /// Defaults to `['GET']`. Collapsing two identical `POST`s would drop a
  /// request the caller meant to send twice, so non-idempotent methods stay
  /// out unless explicitly listed.
  final List<String> methods;

  /// Request headers whose value scopes the deduplication key.
  ///
  /// Same default and same reason as `CacheConfig.varyHeaders`: two concurrent
  /// requests sent either side of an identity change must not collapse into
  /// one, or the second caller receives the first caller's body. The window is
  /// narrower than the cache's — it closes as soon as both requests finish —
  /// but the wrong answer is identical.
  ///
  /// Only a truncated digest of the value ever reaches the key.
  final List<String> varyHeaders;

  /// Creates a [DeduplicationConfig].
  const DeduplicationConfig({
    this.enabled = true,
    this.methods = const ['GET'],
    this.varyHeaders = const ['Authorization'],
  });

  /// Creates a disabled config.
  factory DeduplicationConfig.disabled() =>
      const DeduplicationConfig(enabled: false);

  /// Returns true if the given HTTP [method] should be deduplicated.
  ///
  /// Comparison is case-insensitive.
  bool shouldDeduplicate(String method) =>
      enabled && methods.contains(method.toUpperCase());

  /// Creates a copy with the given fields replaced.
  DeduplicationConfig copyWith({
    bool? enabled,
    List<String>? methods,
    List<String>? varyHeaders,
  }) {
    return DeduplicationConfig(
      enabled: enabled ?? this.enabled,
      methods: methods ?? this.methods,
      varyHeaders: varyHeaders ?? this.varyHeaders,
    );
  }

  @override
  String toString() => 'DeduplicationConfig(enabled: $enabled, '
      'methods: $methods, varyHeaders: $varyHeaders)';
}
