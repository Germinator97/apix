import 'dart:convert';

import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

/// A reversible stand-in for a real cipher: enough to prove the decorator
/// round-trips and that nothing readable is handed to the delegate.
String _seal(String plain) => base64.encode(utf8.encode('v1:$plain'));

String _open(String sealed) {
  final decoded = utf8.decode(base64.decode(sealed));
  if (!decoded.startsWith('v1:')) {
    throw const FormatException('wrong key');
  }
  return decoded.substring(3);
}

CacheEntry _entry({
  String data = '{"balance":125000,"currency":"XOF"}',
  Map<String, String>? headers,
  Duration ttl = const Duration(minutes: 5),
  String? etag,
}) =>
    CacheEntry.withTtl(
      data: data,
      statusCode: 200,
      ttl: ttl,
      etag: etag,
      headers: headers,
    );

void main() {
  late InMemoryCacheStorage delegate;
  late EncryptedCacheStorage storage;

  setUp(() {
    delegate = InMemoryCacheStorage();
    storage = EncryptedCacheStorage(
      delegate: delegate,
      encrypt: _seal,
      decrypt: _open,
    );
  });

  group('EncryptedCacheStorage', () {
    test('round-trips a body unchanged', () async {
      final original = _entry();
      await storage.set('GET:/balance', original);

      final read = await storage.get('GET:/balance');

      expect(read, isNotNull);
      expect(read!.data, equals(original.data));
      expect(read.statusCode, equals(200));
    });

    // The reason the class exists: what lands in the delegate must not be
    // readable. Asserting only the round-trip would pass on a decorator that
    // encrypts nothing at all.
    test('what reaches the delegate is not the plaintext', () async {
      await storage.set('GET:/balance', _entry());

      final stored = await delegate.get('GET:/balance');

      expect(stored, isNotNull);
      expect(stored!.data, isNot(contains('125000')));
      expect(stored.data, isNot(contains('balance')));
      expect(stored.data, isNot(contains('XOF')));
    });

    test('headers are sealed too, and come back intact', () async {
      await storage.set(
        'GET:/balance',
        _entry(headers: {'set-cookie': 'session=abc123'}),
      );

      final stored = await delegate.get('GET:/balance');
      expect(stored!.data, isNot(contains('session=abc123')));
      expect(stored.headers, isNull);

      final read = await storage.get('GET:/balance');
      expect(read!.headers, equals({'set-cookie': 'session=abc123'}));
    });

    test('expiry metadata stays readable without a key', () async {
      final original = _entry(etag: 'W/"v1"');
      await storage.set('GET:/balance', original);

      final stored = await delegate.get('GET:/balance');

      // has() must be answerable without decrypting every entry.
      expect(stored!.expiresAt, equals(original.expiresAt));
      expect(stored.etag, equals('W/"v1"'));
      expect(stored.isValid, isTrue);
    });

    group('unreadable entries', () {
      test('a wrong key reads as a miss, not an exception', () async {
        await storage.set('GET:/balance', _entry());

        final wrongKey = EncryptedCacheStorage(
          delegate: delegate,
          encrypt: _seal,
          decrypt: (_) => throw const FormatException('wrong key'),
        );

        expect(await wrongKey.get('GET:/balance'), isNull);
      });

      test('a corrupted entry reads as a miss', () async {
        await delegate.set('GET:/balance', _entry(data: 'not-sealed-at-all'));

        expect(await storage.get('GET:/balance'), isNull);
      });

      // Left in place, an unreadable entry would fail forever on the same
      // bytes: the next write could not replace what get() never admits exists.
      test('an unreadable entry is purged on read', () async {
        await delegate.set('GET:/balance', _entry(data: 'garbage'));

        await storage.get('GET:/balance');

        expect(await delegate.get('GET:/balance'), isNull);
      });

      test('has() reports an undecryptable entry as absent', () async {
        await delegate.set('GET:/balance', _entry(data: 'garbage'));

        expect(
          await storage.has('GET:/balance'),
          isFalse,
          reason: 'answering true here and null from get() is how a caller '
              'ends up trusting a hit that never arrives',
        );
      });
    });

    group('the invalidation API keeps working', () {
      setUp(() async {
        await storage.set('GET:https://api.test/users/1', _entry());
        await storage.set('GET:https://api.test/users/2', _entry());
        await storage.set('GET:https://api.test/balance', _entry());
      });

      test('keys are readable, so they can be matched', () async {
        expect(await storage.keys(), hasLength(3));
        expect(
          await storage.keys(),
          contains('GET:https://api.test/balance'),
          reason: 'opaque keys would break removeWhere/removeByPrefix and the '
              'whole invalidateUrl API built on them',
        );
      });

      test('removeByPrefix still matches', () async {
        expect(
          await storage.removeByPrefix('GET:https://api.test/users'),
          equals(2),
        );
        expect(await storage.keys(), hasLength(1));
      });

      test('removeWhere still matches', () async {
        expect(
          await storage.removeWhere((k) => k.contains('/balance')),
          equals(1),
        );
      });

      test('remove and clear pass through', () async {
        await storage.remove('GET:https://api.test/balance');
        expect(await storage.keys(), hasLength(2));

        await storage.clear();
        expect(await storage.keys(), isEmpty);
      });
    });

    test('has() follows the delegate on expiry', () async {
      await storage.set(
        'GET:/stale',
        _entry(ttl: const Duration(milliseconds: -1)),
      );

      expect(await storage.has('GET:/stale'), isFalse);
    });

    // Expired entries must still be *retrievable*: cacheFirst serves them while
    // revalidating, networkFirst as an offline fallback. Encryption must not
    // quietly turn that into a miss.
    test('an expired entry is still returned by get()', () async {
      await storage.set(
        'GET:/stale',
        _entry(ttl: const Duration(milliseconds: -1)),
      );

      final read = await storage.get('GET:/stale');

      expect(read, isNotNull);
      expect(read!.isExpired, isTrue);
    });
  });
}
