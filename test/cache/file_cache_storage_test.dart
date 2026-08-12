import 'dart:convert';
import 'dart:io';

import 'package:apix/apix.dart';
import 'package:dio/dio.dart'
    show Headers, HttpClientAdapter, RequestOptions, ResponseBody;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late FileCacheStorage storage;

  CacheEntry fresh([String body = '{"id":1}']) => CacheEntry.withTtl(
        data: body,
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      );

  CacheEntry expired([String body = '{"id":1}']) => CacheEntry(
        data: body,
        statusCode: 200,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('apix_file_cache_test');
    storage = FileCacheStorage(dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('persistence', () {
    test('an entry written by one instance is read by the next', () async {
      // The whole point of this storage: a cold start still has the data.
      // A test that reuses the same instance would prove nothing.
      await storage.set('GET:/users', fresh('{"name":"Ada"}'));

      final afterRestart = FileCacheStorage(dir);
      final entry = await afterRestart.get('GET:/users');

      expect(entry, isNotNull);
      expect(entry!.data, '{"name":"Ada"}');
      expect(entry.statusCode, 200);
    });

    test('creates its directory on first write', () async {
      final nested = Directory('${dir.path}/does/not/exist/yet');
      final target = FileCacheStorage(nested);

      await target.set('GET:/a', fresh());

      expect(nested.existsSync(), isTrue);
      expect((await target.get('GET:/a'))!.data, '{"id":1}');
    });

    test('reading a directory that was never written is a plain miss',
        () async {
      final absent = FileCacheStorage(Directory('${dir.path}/nope'));

      expect(await absent.get('GET:/a'), isNull);
      expect(await absent.keys(), isEmpty);
      expect(await absent.has('GET:/a'), isFalse);
      await absent.clear(); // must not throw
    });

    test('keys survive the round-trip even though filenames are digests',
        () async {
      await storage.set('GET:https://api.test/users?page=2', fresh());

      expect(await storage.keys(), ['GET:https://api.test/users?page=2']);
    });
  });

  group('expiry is not the storage\'s business', () {
    test('get returns an expired entry, has() does not', () async {
      await storage.set('GET:/stale', expired());

      final entry = await storage.get('GET:/stale');
      expect(
        entry,
        isNotNull,
        reason: 'the interceptor owns the TTL and needs the stale body',
      );
      expect(entry!.isExpired, isTrue);
      expect(await storage.has('GET:/stale'), isFalse);
    });

    test('keys() reports expired entries and removes nothing', () async {
      await storage.set('GET:/fresh', fresh());
      await storage.set('GET:/stale', expired());

      expect(
        (await storage.keys())..sort(),
        ['GET:/fresh', 'GET:/stale'],
        reason: 'expiry is the interceptor\'s business here too',
      );
      expect(
        await storage.get('GET:/stale'),
        isNotNull,
        reason: 'this used to sweep, so listing the keys destroyed the very '
            'entries networkFirst serves when the network is gone',
      );
    });

    test('keys() still discards a file that can never become an entry',
        () async {
      await storage.set('GET:/good', fresh());
      File('${dir.path}/${'0' * 64}.json').writeAsStringSync('not json at all');

      expect(await storage.keys(), ['GET:/good']);
      expect(
        dir.listSync().whereType<File>().length,
        1,
        reason: 'unreadable is not the same as stale: it has no key to report '
            'and can never acquire one',
      );
    });
  });

  group('corruption never escapes as an exception', () {
    /// Writes [content] under the filename [storage] would use for [key].
    Future<File> corrupt(String key, String content) async {
      await storage.set(key, fresh());
      final file = dir
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.json'));
      file.writeAsStringSync(content);
      return file;
    }

    test('truncated JSON is a miss, and the file is discarded', () async {
      final file = await corrupt('GET:/x', '{"key":"GET:/x","ent');

      expect(await storage.get('GET:/x'), isNull);
      expect(file.existsSync(), isFalse, reason: 'must not be re-read forever');
    });

    test('valid JSON of the wrong shape is a miss', () async {
      await corrupt('GET:/x', '["not", "an", "object"]');

      expect(await storage.get('GET:/x'), isNull);
    });

    test('an entry with missing fields is a miss', () async {
      await corrupt('GET:/x',
          jsonEncode({'key': 'GET:/x', 'entry': <String, dynamic>{}}));

      expect(await storage.get('GET:/x'), isNull);
    });

    test('a corrupted file does not break keys() for the others', () async {
      await storage.set('GET:/good', fresh());
      File('${dir.path}/${'a' * 64}.json').writeAsStringSync('{oops');

      expect(await storage.keys(), ['GET:/good']);
    });
  });

  group('it only touches its own files', () {
    test('clear leaves foreign files alone', () async {
      await storage.set('GET:/mine', fresh());
      final foreign = File('${dir.path}/not-ours.txt')
        ..writeAsStringSync('keep me');

      await storage.clear();

      expect(await storage.keys(), isEmpty);
      expect(
        foreign.existsSync(),
        isTrue,
        reason: 'the directory may be shared with anything else',
      );
    });
  });

  group('removal', () {
    test('remove deletes a single entry', () async {
      await storage.set('GET:/a', fresh());
      await storage.set('GET:/b', fresh());

      await storage.remove('GET:/a');

      expect(await storage.get('GET:/a'), isNull);
      expect(await storage.get('GET:/b'), isNotNull);
    });

    test('removeByPrefix removes the matching entries and counts them',
        () async {
      await storage.set('GET:https://api.test/users/1', fresh());
      await storage.set('GET:https://api.test/users/2', fresh());
      await storage.set('GET:https://api.test/posts/1', fresh());

      final removed =
          await storage.removeByPrefix('GET:https://api.test/users');

      expect(removed, 2);
      expect(await storage.keys(), ['GET:https://api.test/posts/1']);
    });

    test('removeWhere honours an arbitrary predicate', () async {
      await storage.set('GET:/a', fresh());
      await storage.set('POST:/a', fresh());

      final removed = await storage.removeWhere((k) => k.startsWith('POST:'));

      expect(removed, 1);
      expect(await storage.keys(), ['GET:/a']);
    });

    test('removing an absent key is a no-op', () async {
      await storage.remove('GET:/never-existed');
      expect(await storage.keys(), isEmpty);
    });
  });

  group('bounded by default', () {
    test('the cap is on by default — a disk cache must not grow forever',
        () async {
      // Unlike an in-memory cache, this one outlives the process. Shipping it
      // unbounded would keep every response ever made until something else
      // cleared it.
      expect(FileCacheStorage(dir).maxEntries, isNotNull);
    });

    test('keeps at most maxEntries', () async {
      final bounded = FileCacheStorage(dir, maxEntries: 3);

      for (var i = 0; i < 10; i++) {
        await bounded.set('GET:/item/$i', fresh('{"i":$i}'));
      }

      expect(await bounded.keys(), hasLength(3));
      expect(dir.listSync().whereType<File>().length, 3);
    });

    test('evicts expired entries before valid ones', () async {
      final bounded = FileCacheStorage(dir, maxEntries: 2);

      await bounded.set('GET:/stale', expired());
      await bounded.set('GET:/keep-a', fresh('{"k":"a"}'));
      // Third write trips the cap: the expired entry must be the one to go.
      await bounded.set('GET:/keep-b', fresh('{"k":"b"}'));

      final keys = await bounded.keys();
      expect(keys, hasLength(2));
      expect(keys, containsAll(<String>['GET:/keep-a', 'GET:/keep-b']));
      expect(await bounded.get('GET:/stale'), isNull);
    });

    test('rewriting the same key never trips the cap', () async {
      final bounded = FileCacheStorage(dir, maxEntries: 1);

      await bounded.set('GET:/a', fresh('{"v":1}'));
      await bounded.set('GET:/a', fresh('{"v":2}'));
      await bounded.set('GET:/a', fresh('{"v":3}'));

      expect(await bounded.keys(), ['GET:/a']);
      expect((await bounded.get('GET:/a'))!.data, '{"v":3}');
    });

    test('maxEntries: null opts out of the cap', () async {
      final unbounded = FileCacheStorage(dir, maxEntries: null);

      for (var i = 0; i < 12; i++) {
        await unbounded.set('GET:/item/$i', fresh('{"i":$i}'));
      }

      expect(await unbounded.keys(), hasLength(12));
    });

    test('rejects a non-positive cap instead of silently keeping nothing', () {
      expect(() => FileCacheStorage(dir, maxEntries: 0), throwsA(anything));
    });
  });

  test('a rewritten key replaces its entry rather than piling up', () async {
    await storage.set('GET:/a', fresh('{"v":1}'));
    await storage.set('GET:/a', fresh('{"v":2}'));

    expect((await storage.get('GET:/a'))!.data, '{"v":2}');
    expect(dir.listSync().whereType<File>().length, 1);
  });

  test('works as the storage of a real client, across a restart', () async {
    // End-to-end: the interceptor's cache key is opaque to this test, which is
    // precisely why it is worth going through the client rather than crafting
    // the key by hand.
    ApiClient buildClient(FileCacheStorage s) => ApiClientFactory.create(
          baseUrl: 'https://cache.test.local',
          cacheConfig: CacheConfig(
            storage: s,
            strategy: CacheStrategy.cacheFirst,
            defaultTtl: const Duration(minutes: 5),
          ),
          httpClientAdapter: _OnceAdapter(),
        );

    final first = await buildClient(storage).get<dynamic>('/items');
    expect(first.isFromCache, isFalse);

    // New storage instance over the same directory = a cold start.
    final second =
        await buildClient(FileCacheStorage(dir)).get<dynamic>('/items');
    expect(
      second.isFromCache,
      isTrue,
      reason: 'this is what InMemoryCacheStorage could never do',
    );
    expect(second.isStale, isFalse);
  });
}

/// Answers a fixed body; fails if called more than once, so a test that
/// expects a cache hit cannot pass by silently re-fetching.
class _OnceAdapter implements HttpClientAdapter {
  int hits = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    hits++;
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'hit': hits})),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
