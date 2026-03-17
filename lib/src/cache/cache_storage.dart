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
}

/// In-memory implementation of [CacheStorage].
///
/// Suitable for testing and short-lived caches that don't need persistence.
class InMemoryCacheStorage implements CacheStorage {
  final Map<String, CacheEntry> _cache = {};

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

  /// Returns the current number of cached entries.
  int get length => _cache.length;
}
