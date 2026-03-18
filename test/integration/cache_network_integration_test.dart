import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cache Integration Tests', () {
    group('InMemoryCacheStorage', () {
      late InMemoryCacheStorage storage;

      setUp(() {
        storage = InMemoryCacheStorage();
      });

      test('stores and retrieves cache entries', () async {
        final entry = CacheEntry.withTtl(
          data: '{"test": true}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
        );

        await storage.set('test-key', entry);
        final retrieved = await storage.get('test-key');

        expect(retrieved, isNotNull);
        expect(retrieved!.data, '{"test": true}');
        expect(retrieved.statusCode, 200);
      });

      test('returns null for missing keys', () async {
        final result = await storage.get('nonexistent');
        expect(result, isNull);
      });

      test('removes entries', () async {
        final entry = CacheEntry.withTtl(
          data: '{}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
        );

        await storage.set('key', entry);
        await storage.remove('key');
        final result = await storage.get('key');

        expect(result, isNull);
      });

      test('clears all entries', () async {
        await storage.set('key1', CacheEntry.withTtl(
          data: '{}', statusCode: 200, ttl: const Duration(minutes: 5)));
        await storage.set('key2', CacheEntry.withTtl(
          data: '{}', statusCode: 200, ttl: const Duration(minutes: 5)));

        await storage.clear();

        expect(await storage.get('key1'), isNull);
        expect(await storage.get('key2'), isNull);
      });

      test('checks if key exists', () async {
        await storage.set('exists', CacheEntry.withTtl(
          data: '{}', statusCode: 200, ttl: const Duration(minutes: 5)));

        expect(await storage.has('exists'), true);
        expect(await storage.has('missing'), false);
      });
    });

    group('CacheEntry', () {
      test('isExpired returns true for expired entries', () {
        final expired = CacheEntry(
          data: '{}',
          statusCode: 200,
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
          expiresAt: DateTime.now().subtract(const Duration(minutes: 30)),
        );

        expect(expired.isExpired, true);
        expect(expired.isValid, false);
      });

      test('isExpired returns false for valid entries', () {
        final valid = CacheEntry.withTtl(
          data: '{}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
        );

        expect(valid.isExpired, false);
        expect(valid.isValid, true);
      });

      test('remainingTtl returns correct duration', () {
        final entry = CacheEntry.withTtl(
          data: '{}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
        );

        expect(entry.remainingTtl.inMinutes, greaterThanOrEqualTo(4));
      });

      test('serializes to and from JSON', () {
        final entry = CacheEntry.withTtl(
          data: '{"test": true}',
          statusCode: 200,
          ttl: const Duration(minutes: 5),
          etag: 'abc123',
        );

        final json = entry.toJson();
        final restored = CacheEntry.fromJson(json);

        expect(restored.data, entry.data);
        expect(restored.statusCode, entry.statusCode);
        expect(restored.etag, entry.etag);
      });
    });

    group('CacheConfig', () {
      test('default values are sensible', () {
        final config = CacheConfig();

        expect(config.strategy, CacheStrategy.networkFirst);
        expect(config.defaultTtl, const Duration(minutes: 5));
        expect(config.cacheErrors, false);
        expect(config.enableDeduplication, true);
      });

      test('shouldCache filters by method', () {
        final config = CacheConfig(cacheableMethods: ['GET', 'HEAD']);

        expect(config.shouldCache('GET'), true);
        expect(config.shouldCache('HEAD'), true);
        expect(config.shouldCache('POST'), false);
      });

      test('shouldDeduplicate respects enableDeduplication', () {
        final enabled = CacheConfig(enableDeduplication: true);
        final disabled = CacheConfig(enableDeduplication: false);

        expect(enabled.shouldDeduplicate('GET'), true);
        expect(disabled.shouldDeduplicate('GET'), false);
      });
    });

    group('CacheStrategy', () {
      test('all strategies are defined', () {
        expect(CacheStrategy.values, contains(CacheStrategy.cacheFirst));
        expect(CacheStrategy.values, contains(CacheStrategy.networkFirst));
        expect(CacheStrategy.values, contains(CacheStrategy.httpCacheAware));
        expect(CacheStrategy.values, contains(CacheStrategy.networkOnly));
        expect(CacheStrategy.values, contains(CacheStrategy.cacheOnly));
      });
    });
  });
}
