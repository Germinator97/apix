import 'cache_entry.dart';

/// Abstract interface for cache storage backends.
///
/// Implement this interface to provide custom storage for cached responses.
/// The default implementation uses in-memory storage.
///
/// Example:
/// ```dart
/// class SharedPrefsCacheStorage implements CacheStorage {
///   final SharedPreferences _prefs;
///
///   @override
///   Future<CacheEntry?> get(String key) async {
///     final json = _prefs.getString(key);
///     if (json == null) return null;
///     return CacheEntry.fromJson(jsonDecode(json));
///   }
///
///   // ... other methods
/// }
/// ```
abstract class CacheStorage {
  /// Retrieves a cached entry by key, **expired or not**.
  ///
  /// Returns null only when the key doesn't exist. Expiry is **not** a storage
  /// concern: `CacheInterceptor` decides what to do with a stale entry, because
  /// the right answer depends on the strategy — `cacheFirst` serves it while
  /// revalidating, `networkFirst` serves it only as an offline fallback, and
  /// `cacheOnly` refuses it.
  ///
  /// This used to be the storage's job, and that made the TTL a guarantee only
  /// as strong as the implementation: any backend that forgot to filter made
  /// `defaultTtl` silently inoperative. Implementations must now simply store
  /// and return.
  Future<CacheEntry?> get(String key);

  /// Stores a cache entry with the given key.
  Future<void> set(String key, CacheEntry entry);

  /// Removes a specific cache entry.
  Future<void> remove(String key);

  /// Clears all cached entries.
  Future<void> clear();

  /// Returns true if a **valid (non-expired)** entry exists for the key.
  ///
  /// Unlike [get], this one does filter on expiry — it answers "is there
  /// usable fresh data here?", which is the only question worth asking of a
  /// boolean.
  Future<bool> has(String key);

  /// Returns every stored key, **expired or not**, and removes nothing.
  ///
  /// Reading must not delete. Both built-in backends used to purge expired
  /// entries while walking, which made a listing destructive in a way its name
  /// gave no hint of — and destructive of the wrong thing: an expired entry is
  /// exactly what `networkFirst` serves when the network is gone, and what
  /// `cacheFirst` serves while it revalidates. Calling `getCacheKeys()` to see
  /// what was cached therefore threw away the offline fallback, silently,
  /// leaving a cache miss where there had been data.
  ///
  /// Use `CacheInterceptor.evictExpired()` when removing them is the intent.
  Future<List<String>> keys();

  /// Removes all entries matching the given pattern.
  ///
  /// The pattern can be a prefix (e.g., 'GET:https://api.com/users')
  /// or contain wildcards using '*' (e.g., 'GET:*/users/*').
  Future<int> removeWhere(bool Function(String key) predicate);

  /// Removes all entries whose keys start with the given prefix.
  Future<int> removeByPrefix(String prefix);
}

/// In-memory implementation of [CacheStorage].
///
/// Suitable for testing and short-lived caches that don't need persistence.
///
/// When [maxEntries] is set, the oldest entries are evicted when the limit
/// is exceeded (FIFO eviction).
class InMemoryCacheStorage implements CacheStorage {
  final Map<String, CacheEntry> _cache = {};

  /// Maximum number of entries to keep. `null` means unlimited.
  final int? maxEntries;

  /// Creates an [InMemoryCacheStorage] with an optional size limit.
  InMemoryCacheStorage({this.maxEntries});

  @override
  Future<CacheEntry?> get(String key) async {
    // Expired entries are returned, not purged: the interceptor needs them to
    // serve stale-while-revalidating and offline fallbacks. See [CacheStorage.get].
    return _cache[key];
  }

  @override
  Future<void> set(String key, CacheEntry entry) async {
    _cache[key] = entry;
    _evictIfNeeded();
  }

  /// Evicts entries when the cache exceeds [maxEntries].
  ///
  /// Expired entries go first — they are the ones least likely to be served
  /// again — then the oldest inserted (FIFO). Evicting purely by insertion
  /// order would drop a fresh entry while keeping a stale one.
  void _evictIfNeeded() {
    if (maxEntries == null || _cache.length <= maxEntries!) return;

    var excess = _cache.length - maxEntries!;

    final expired = _cache.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .take(excess)
        .toList();
    for (final key in expired) {
      _cache.remove(key);
    }

    excess -= expired.length;
    if (excess <= 0) return;

    for (final key in _cache.keys.take(excess).toList()) {
      _cache.remove(key);
    }
  }

  @override
  Future<void> remove(String key) async {
    _cache.remove(key);
  }

  @override
  Future<void> clear() async {
    _cache.clear();
  }

  @override
  Future<bool> has(String key) async {
    final entry = _cache[key];
    // Filters explicitly rather than delegating to [get], which no longer
    // rejects expired entries.
    return entry != null && entry.isValid;
  }

  @override
  Future<List<String>> keys() async {
    // Returns expired entries and removes nothing — see [CacheStorage.keys].
    return _cache.keys.toList();
  }

  @override
  Future<int> removeWhere(bool Function(String key) predicate) async {
    final keysToRemove = _cache.keys.where(predicate).toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
    return keysToRemove.length;
  }

  @override
  Future<int> removeByPrefix(String prefix) async {
    return removeWhere((key) => key.startsWith(prefix));
  }

  /// Returns the current number of cached entries.
  int get length => _cache.length;
}
