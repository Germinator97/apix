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
  /// Retrieves a cached entry by key.
  ///
  /// Returns null if the key doesn't exist or the entry has expired.
  Future<CacheEntry?> get(String key);

  /// Stores a cache entry with the given key.
  Future<void> set(String key, CacheEntry entry);

  /// Removes a specific cache entry.
  Future<void> remove(String key);

  /// Clears all cached entries.
  Future<void> clear();

  /// Returns true if a valid (non-expired) entry exists for the key.
  Future<bool> has(String key);

  /// Returns all cached keys.
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
    final entry = _cache[key];
    if (entry == null) return null;

    // Auto-remove expired entries
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }

    return entry;
  }

  @override
  Future<void> set(String key, CacheEntry entry) async {
    _cache[key] = entry;
    _evictIfNeeded();
  }

  /// Evicts oldest entries when the cache exceeds [maxEntries].
  void _evictIfNeeded() {
    if (maxEntries == null || _cache.length <= maxEntries!) return;
    final excess = _cache.length - maxEntries!;
    final keysToRemove = _cache.keys.take(excess).toList();
    for (final key in keysToRemove) {
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
    final entry = await get(key);
    return entry != null;
  }

  @override
  Future<List<String>> keys() async {
    // Filter out expired entries
    _cache.removeWhere((_, entry) => entry.isExpired);
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
