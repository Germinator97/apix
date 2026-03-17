import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('CacheEntry', () {
    test('creates with required fields', () {
      final now = DateTime.now();
      final entry = CacheEntry(
        data: '{"id": 1}',
        statusCode: 200,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      );

      expect(entry.data, equals('{"id": 1}'));
      expect(entry.statusCode, equals(200));
      expect(entry.createdAt, equals(now));
      expect(entry.isValid, isTrue);
    });

    test('creates with TTL factory', () {
      final entry = CacheEntry.withTtl(
        data: '{"id": 1}',
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      );

      expect(entry.isValid, isTrue);
      expect(entry.remainingTtl.inMinutes, greaterThanOrEqualTo(4));
    });

    test('isExpired returns true for expired entry', () {
      final entry = CacheEntry(
        data: '{"id": 1}',
        statusCode: 200,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      expect(entry.isExpired, isTrue);
      expect(entry.isValid, isFalse);
    });

    test('remainingTtl returns zero for expired entry', () {
      final entry = CacheEntry(
        data: '{"id": 1}',
        statusCode: 200,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      expect(entry.remainingTtl, equals(Duration.zero));
    });

    test('toJson and fromJson roundtrip', () {
      final entry = CacheEntry.withTtl(
        data: '{"id": 1}',
        statusCode: 200,
        ttl: const Duration(minutes: 5),
        etag: 'abc123',
        headers: {'content-type': 'application/json'},
      );

      final json = entry.toJson();
      final restored = CacheEntry.fromJson(json);

      expect(restored.data, equals(entry.data));
      expect(restored.statusCode, equals(entry.statusCode));
      expect(restored.etag, equals(entry.etag));
      expect(restored.headers, equals(entry.headers));
    });

    test('copyWith creates updated copy', () {
      final entry = CacheEntry.withTtl(
        data: '{"id": 1}',
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      );

      final updated = entry.copyWith(statusCode: 201);

      expect(updated.statusCode, equals(201));
      expect(updated.data, equals(entry.data));
    });
  });

  group('InMemoryCacheStorage', () {
    late InMemoryCacheStorage storage;

    setUp(() {
      storage = InMemoryCacheStorage();
    });

    test('get returns null for missing key', () async {
      final result = await storage.get('missing');
      expect(result, isNull);
    });

    test('set and get stores and retrieves entry', () async {
      final entry = CacheEntry.withTtl(
        data: '{"id": 1}',
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      );

      await storage.set('key1', entry);
      final result = await storage.get('key1');

      expect(result, isNotNull);
      expect(result!.data, equals('{"id": 1}'));
    });

    test('get returns null for expired entry', () async {
      final entry = CacheEntry(
        data: '{"id": 1}',
        statusCode: 200,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await storage.set('expired', entry);
      final result = await storage.get('expired');

      expect(result, isNull);
    });

    test('remove deletes entry', () async {
      final entry = CacheEntry.withTtl(
        data: '{"id": 1}',
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      );

      await storage.set('key1', entry);
      await storage.remove('key1');
      final result = await storage.get('key1');

      expect(result, isNull);
    });

    test('clear removes all entries', () async {
      final entry = CacheEntry.withTtl(
        data: '{"id": 1}',
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      );

      await storage.set('key1', entry);
      await storage.set('key2', entry);
      await storage.clear();

      expect(storage.length, equals(0));
    });

    test('has returns true for existing valid entry', () async {
      final entry = CacheEntry.withTtl(
        data: '{"id": 1}',
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      );

      await storage.set('key1', entry);

      expect(await storage.has('key1'), isTrue);
      expect(await storage.has('missing'), isFalse);
    });

    test('keys returns all valid keys', () async {
      final entry = CacheEntry.withTtl(
        data: '{"id": 1}',
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      );

      await storage.set('key1', entry);
      await storage.set('key2', entry);

      final allKeys = await storage.keys();

      expect(allKeys, containsAll(['key1', 'key2']));
    });

    test('removeWhere removes matching entries', () async {
      final storage = InMemoryCacheStorage();
      final entry = CacheEntry.withTtl(
        data: '{}',
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      );

      await storage.set('GET:https://api.com/users/1', entry);
      await storage.set('GET:https://api.com/users/2', entry);
      await storage.set('GET:https://api.com/posts/1', entry);

      final removed =
          await storage.removeWhere((key) => key.contains('/users'));

      expect(removed, equals(2));
      expect(await storage.has('GET:https://api.com/users/1'), isFalse);
      expect(await storage.has('GET:https://api.com/users/2'), isFalse);
      expect(await storage.has('GET:https://api.com/posts/1'), isTrue);
    });

    test('removeByPrefix removes entries starting with prefix', () async {
      final storage = InMemoryCacheStorage();
      final entry = CacheEntry.withTtl(
        data: '{}',
        statusCode: 200,
        ttl: const Duration(minutes: 5),
      );

      await storage.set('GET:https://api.com/users', entry);
      await storage.set('GET:https://api.com/users/1', entry);
      await storage.set('POST:https://api.com/users', entry);

      final removed = await storage.removeByPrefix('GET:https://api.com/users');

      expect(removed, equals(2));
      expect(await storage.has('GET:https://api.com/users'), isFalse);
      expect(await storage.has('GET:https://api.com/users/1'), isFalse);
      expect(await storage.has('POST:https://api.com/users'), isTrue);
    });
  });

  group('CacheConfig', () {
    test('creates with default values', () {
      final config = CacheConfig();

      expect(config.strategy, equals(CacheStrategy.networkFirst));
      expect(config.defaultTtl, equals(const Duration(minutes: 5)));
      expect(config.cacheErrors, isFalse);
      expect(config.cacheableMethods, equals(['GET']));
      expect(config.storage, isA<InMemoryCacheStorage>());
    });

    test('creates with custom values', () {
      final storage = InMemoryCacheStorage();
      final config = CacheConfig(
        storage: storage,
        strategy: CacheStrategy.cacheFirst,
        defaultTtl: const Duration(hours: 1),
        cacheErrors: true,
        cacheableMethods: ['GET', 'POST'],
      );

      expect(config.storage, equals(storage));
      expect(config.strategy, equals(CacheStrategy.cacheFirst));
      expect(config.defaultTtl, equals(const Duration(hours: 1)));
      expect(config.cacheErrors, isTrue);
      expect(config.cacheableMethods, equals(['GET', 'POST']));
    });

    test('shouldCache returns true for cacheable methods', () {
      final config = CacheConfig(cacheableMethods: ['GET', 'HEAD']);

      expect(config.shouldCache('GET'), isTrue);
      expect(config.shouldCache('get'), isTrue);
      expect(config.shouldCache('HEAD'), isTrue);
      expect(config.shouldCache('POST'), isFalse);
    });

    test('copyWith creates updated config', () {
      final config = CacheConfig();
      final updated = config.copyWith(
        strategy: CacheStrategy.cacheFirst,
      );

      expect(updated.strategy, equals(CacheStrategy.cacheFirst));
      expect(updated.defaultTtl, equals(config.defaultTtl));
    });

    test('CacheStrategy has all expected values', () {
      expect(CacheStrategy.values, contains(CacheStrategy.cacheFirst));
      expect(CacheStrategy.values, contains(CacheStrategy.networkFirst));
      expect(CacheStrategy.values, contains(CacheStrategy.httpCacheAware));
      expect(CacheStrategy.values, contains(CacheStrategy.networkOnly));
      expect(CacheStrategy.values, contains(CacheStrategy.cacheOnly));
    });
  });
}
