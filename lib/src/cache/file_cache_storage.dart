import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'cache_entry.dart';
import 'cache_storage.dart';

/// A [CacheStorage] that survives process restarts by writing one JSON file
/// per entry.
///
/// The caller supplies the directory, so apix pulls in **no new dependency**:
/// pass whatever your app already resolves, typically
/// `await getTemporaryDirectory()` from `path_provider`.
///
/// ```dart
/// final dir = await getTemporaryDirectory();
/// final client = ApiClientFactory.create(
///   baseUrl: 'https://api.example.com',
///   cacheConfig: CacheConfig(
///     storage: FileCacheStorage(Directory('${dir.path}/apix_cache')),
///     strategy: CacheStrategy.cacheFirst,
///   ),
/// );
/// ```
///
/// ## Not for sensitive data
///
/// Entries are stored **in clear text**, readable by anything that can reach
/// the directory. Never point this at responses carrying credentials, tokens,
/// personal data or amounts you would not write to a log. Those either belong
/// in `flutter_secure_storage` — which is sized for small secrets, not HTTP
/// bodies — or should not be cached at all. Prefer a cache directory the OS is
/// allowed to purge over a documents directory that gets backed up.
///
/// ## Behaviour
///
/// - Reads never throw: an unreadable or corrupted file is treated as a cache
///   miss, and the file is deleted so it stops being read.
/// - Writes are atomic (write to a temporary file, then rename), so a reader
///   never observes a half-written entry.
/// - Like every [CacheStorage], this one does **not** filter on expiry — the
///   interceptor owns the TTL. See [CacheStorage.get].
/// - [maxEntries] caps how many entries are kept. **It defaults to a bound**,
///   unlike [InMemoryCacheStorage]: a process cache disappears when the app
///   closes, a disk cache does not. Left unbounded, this one would grow for
///   the lifetime of the install.
class FileCacheStorage implements CacheStorage {
  /// Directory holding the cache files. Created on first write if missing.
  final Directory directory;

  /// Maximum number of entries kept on disk. `null` disables the cap.
  ///
  /// Defaults to 200. When the limit is passed, expired entries are deleted
  /// first, then the least recently written ones.
  ///
  /// Disabling it is a deliberate choice, not a default: an unbounded cache on
  /// disk keeps every response the app has ever made until something else
  /// clears it. Bounding by **count** is a coarse proxy for size — one entry
  /// holds one response body, so a few large payloads still add up. Size-aware
  /// eviction is tracked separately.
  final int? maxEntries;

  /// Creates a [FileCacheStorage] writing into [directory].
  FileCacheStorage(this.directory, {this.maxEntries = 200})
      : assert(maxEntries == null || maxEntries > 0,
            'maxEntries must be positive, or null to disable the cap');

  /// Files written by this storage: a sha256 hex digest plus `.json`.
  ///
  /// Matching on the shape means [clear] and the sweeps below never touch a
  /// neighbouring file, which matters when the caller points several caches —
  /// or something else entirely — at the same directory.
  static final RegExp _ownedFile = RegExp(r'^[0-9a-f]{64}\.json$');

  File _fileFor(String key) {
    final digest = sha256.convert(utf8.encode(key)).toString();
    return File('${directory.path}${Platform.pathSeparator}$digest.json');
  }

  @override
  Future<CacheEntry?> get(String key) async {
    final file = _fileFor(key);
    try {
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        await _discard(file);
        return null;
      }
      final raw = decoded['entry'];
      if (raw is! Map<String, dynamic>) {
        await _discard(file);
        return null;
      }
      final entry = CacheEntry.tryFromJson(raw);
      if (entry == null) await _discard(file);
      return entry;
    } catch (_) {
      // Unreadable file, bad JSON, permission error: a cache miss is always a
      // recoverable outcome, an exception out of a read is not.
      await _discard(file);
      return null;
    }
  }

  @override
  Future<void> set(String key, CacheEntry entry) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    final file = _fileFor(key);
    // The original key is stored alongside the entry: the filename is a
    // digest, so it cannot be reversed, and [keys] would have nothing to
    // return without it.
    final payload = jsonEncode({'key': key, 'entry': entry.toJson()});

    // Write then rename, so a concurrent reader sees either the old entry or
    // the new one — never a truncated file.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(payload, flush: true);
    await temp.rename(file.path);

    await _evictIfNeeded();
  }

  /// Deletes entries once the directory holds more than [maxEntries].
  ///
  /// Expired ones go first — they are the least likely to be served again —
  /// then the oldest written. Runs after each write, which is the only moment
  /// the count can grow.
  Future<void> _evictIfNeeded() async {
    final limit = maxEntries;
    if (limit == null) return;

    final files = <File>[];
    await for (final file in _ownedFiles()) {
      files.add(file);
    }
    if (files.length <= limit) return;

    var excess = files.length - limit;

    // Expired first.
    for (final file in files.toList()) {
      if (excess == 0) break;
      final record = await _readRecord(file);
      if (record == null || record.entry.isExpired) {
        await _discard(file);
        files.remove(file);
        excess--;
      }
    }
    if (excess == 0) return;

    // Then the oldest written. `lastModified` is what the filesystem knows;
    // the entry's own createdAt would need a read per file for no better
    // ordering, since both move together on every write.
    final byAge = <MapEntry<File, DateTime>>[];
    for (final file in files) {
      try {
        byAge.add(MapEntry(file, file.lastModifiedSync()));
      } catch (_) {
        // Vanished under us: nothing left to evict.
      }
    }
    byAge.sort((a, b) => a.value.compareTo(b.value));

    for (final entry in byAge.take(excess)) {
      await _discard(entry.key);
    }
  }

  @override
  Future<void> remove(String key) async {
    await _discard(_fileFor(key));
  }

  @override
  Future<void> clear() async {
    await for (final file in _ownedFiles()) {
      await _discard(file);
    }
  }

  @override
  Future<bool> has(String key) async {
    final entry = await get(key);
    // Filters on expiry, unlike [get] — see [CacheStorage.has].
    return entry != null && entry.isValid;
  }

  @override
  Future<List<String>> keys() async {
    final result = <String>[];
    await for (final file in _ownedFiles()) {
      final record = await _readRecord(file);
      if (record == null) continue;
      // Expired entries are swept here, as the in-memory storage does: this is
      // the only method that walks everything, so it is the natural place to
      // keep the directory from growing without bound.
      if (record.entry.isExpired) {
        await _discard(file);
        continue;
      }
      result.add(record.key);
    }
    return result;
  }

  @override
  Future<int> removeWhere(bool Function(String key) predicate) async {
    var removed = 0;
    await for (final file in _ownedFiles()) {
      final record = await _readRecord(file);
      if (record == null) continue;
      if (predicate(record.key)) {
        await _discard(file);
        removed++;
      }
    }
    return removed;
  }

  @override
  Future<int> removeByPrefix(String prefix) {
    return removeWhere((key) => key.startsWith(prefix));
  }

  /// Lists the files this storage owns, tolerating a missing directory.
  Stream<File> _ownedFiles() async* {
    if (!directory.existsSync()) return;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (_ownedFile.hasMatch(name)) yield entity;
    }
  }

  /// Reads a file back into its key and entry, or null if unusable.
  Future<_Record?> _readRecord(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final key = decoded['key'];
      final raw = decoded['entry'];
      if (key is! String || raw is! Map<String, dynamic>) return null;
      final entry = CacheEntry.tryFromJson(raw);
      return entry == null ? null : _Record(key, entry);
    } catch (_) {
      return null;
    }
  }

  /// Deletes a file, ignoring the case where it is already gone.
  Future<void> _discard(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A file we cannot delete is a file we will re-read and discard again;
      // failing the caller's request over it would be worse.
    }
  }
}

class _Record {
  const _Record(this.key, this.entry);

  final String key;
  final CacheEntry entry;
}
