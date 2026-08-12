import 'dart:convert';

import 'cache_entry.dart';
import 'cache_storage.dart';

/// Transforms a string one way and back — supplied by the caller.
typedef CacheCipher = String Function(String value);

/// Wraps any [CacheStorage] so response bodies are encrypted at rest.
///
/// `FileCacheStorage` writes in clear text, which rules it out wherever the
/// thing worth keeping between launches is also the thing that must not leak —
/// a balance, a medical record, a statement. This decorator closes that gap
/// without apix taking on a crypto dependency or, worse, the responsibility of
/// managing a key: **you** supply [encrypt] and [decrypt], so the algorithm and
/// the key stay in the app that owns them.
///
/// ```dart
/// final storage = EncryptedCacheStorage(
///   delegate: FileCacheStorage(dir),
///   encrypt: (plain) => myCipher.encrypt(plain),
///   decrypt: (cipher) => myCipher.decrypt(cipher),
/// );
/// ```
///
/// ## What is and isn't protected
///
/// Encrypted: the response body and the stored headers — everything that came
/// back from the server.
///
/// **Not encrypted: the cache keys.** They stay in clear text because the whole
/// invalidation API is built on reading them — `keys()`, `removeWhere()`,
/// `removeByPrefix()`, `invalidateUrl()` would all break if they were opaque.
/// A key is `METHOD:url?sorted-query` followed by `|v:<digest>` when
/// `CacheConfig.varyHeaders` is in play, so anything identifying in a *path* or
/// a *query parameter* — `/members/1234/balance`, `?nationalId=...` — remains
/// readable on disk. Where that matters, keep it out of the URL, or don't cache
/// that endpoint.
///
/// The identity fragment is a truncated digest precisely because this is true:
/// it scopes the entry to a caller without writing that caller's bearer token
/// next to it.
///
/// Also unencrypted, and deliberately: status code, timestamps and ETag. The
/// TTL has to be readable without a key, otherwise `has()` and every expiry
/// check would have to decrypt every entry just to learn it was stale.
class EncryptedCacheStorage implements CacheStorage {
  /// The storage doing the actual persisting.
  final CacheStorage delegate;

  /// Applied before writing.
  final CacheCipher encrypt;

  /// Applied after reading. Must be the inverse of [encrypt].
  final CacheCipher decrypt;

  /// Creates an [EncryptedCacheStorage] around [delegate].
  EncryptedCacheStorage({
    required this.delegate,
    required this.encrypt,
    required this.decrypt,
  });

  @override
  Future<void> set(String key, CacheEntry entry) async {
    // Body and headers travel together so a single decrypt round-trips both,
    // and so headers cannot be read while the body they describe stays sealed.
    final sealed = encrypt(jsonEncode({
      'data': entry.data,
      if (entry.headers != null) 'headers': entry.headers,
    }));

    await delegate.set(
      key,
      CacheEntry(
        data: sealed,
        statusCode: entry.statusCode,
        createdAt: entry.createdAt,
        expiresAt: entry.expiresAt,
        etag: entry.etag,
        // Travels in the clear alongside the timestamps: it says how the body
        // was encoded, never anything about what it contains, and the decode
        // path needs it as plainly as the expiry needs its date.
        encoding: entry.encoding,
      ),
    );
  }

  @override
  Future<CacheEntry?> get(String key) async {
    final stored = await delegate.get(key);
    if (stored == null) return null;

    try {
      final opened = jsonDecode(decrypt(stored.data));
      if (opened is! Map) throw const FormatException('not a sealed entry');

      final headers = opened['headers'];
      return CacheEntry(
        data: opened['data'] as String,
        statusCode: stored.statusCode,
        createdAt: stored.createdAt,
        expiresAt: stored.expiresAt,
        etag: stored.etag,
        encoding: stored.encoding,
        headers: headers is Map
            ? headers.map((k, v) => MapEntry(k.toString(), v.toString()))
            : null,
      );
    } catch (_) {
      // A rotated key, a truncated file, or an entry written before encryption
      // was switched on. None of these are recoverable and none should reach
      // the request path as an exception: a cache that cannot be read is a
      // cache miss. Purge it so the next write starts clean rather than
      // failing forever on the same unreadable bytes.
      await delegate.remove(key);
      return null;
    }
  }

  // Key-space operations pass straight through: keys are never transformed.

  @override
  Future<void> remove(String key) => delegate.remove(key);

  @override
  Future<void> clear() => delegate.clear();

  @override
  Future<List<String>> keys() => delegate.keys();

  @override
  Future<int> removeWhere(bool Function(String key) predicate) =>
      delegate.removeWhere(predicate);

  @override
  Future<int> removeByPrefix(String prefix) => delegate.removeByPrefix(prefix);

  /// Whether a **valid, readable** entry exists for [key].
  ///
  /// Stricter than the delegate's own `has`: an entry that is fresh but cannot
  /// be decrypted is reported absent, because that is what [get] will do with
  /// it a moment later. Answering `true` here and `null` there is how a caller
  /// ends up trusting a cache hit that never arrives.
  ///
  /// ⚠️ **This predicate can delete.** Establishing readability means decrypting,
  /// and [get] purges what it cannot open — so asking whether an unreadable
  /// entry exists also removes it. Surprising for a `has`, and kept anyway:
  /// leaving it in place would fail every call forever, since the next write
  /// cannot replace what `get` never admits exists.
  @override
  Future<bool> has(String key) async {
    if (!await delegate.has(key)) return false;
    return await get(key) != null;
  }
}
