import 'package:apix/src/auth/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

/// Guards on the one path in this service that **deletes**.
///
/// `SecureStorageService` recovers from corrupted keychain data by wiping it:
/// `read` drops the offending key, `readAll` drops everything. The decision is
/// made by matching substrings against an exception's `toString()` — so the
/// blast radius of a mistake is a user's session, and the trigger is a string
/// nobody controls.
///
/// A component whose job is to delete cannot be tested in one direction. The
/// over-eager half — wiping a session because an unrelated error happened to
/// carry a matching word — produces a logout, which looks like an expired token
/// and gets reported as one, if at all. So every test here comes in a pair:
/// what must purge, and what must never.
void main() {
  late MockFlutterSecureStorage storage;
  late SecureStorageService service;

  setUp(() {
    storage = MockFlutterSecureStorage();
    service = SecureStorageService(storage: storage);
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
    when(() => storage.deleteAll()).thenAnswer((_) async {});
  });

  /// The strings the service treats as "the stored bytes are unreadable".
  /// Listed here rather than imported so a silent narrowing of the matcher
  /// fails this test instead of passing it.
  const corruptionMessages = [
    'javax.crypto.BadPaddingException: pad block corrupted',
    'BadPaddingException',
    'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
    'Bad Padding',
    'PAD BLOCK CORRUPTED',
  ];

  group('read — recovers from corruption by dropping the key', () {
    for (final message in corruptionMessages) {
      test('purges on: $message', () async {
        when(() => storage.read(key: any(named: 'key')))
            .thenThrow(Exception(message));

        final result = await service.read('apix_access_token');

        expect(result, isNull, reason: 'unreadable is a miss, not a crash');
        verify(() => storage.delete(key: 'apix_access_token')).called(1);
        verifyNever(() => storage.deleteAll());
      });
    }

    test('drops only the affected key, never the whole store', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(Exception('BadPaddingException'));

      await service.read('apix_access_token');

      verifyNever(() => storage.deleteAll());
    });
  });

  group('read — the other direction, where a mistake costs a session', () {
    const unrelatedFailures = [
      'PlatformException(Unexpected error, null, null)',
      'MissingPluginException(No implementation found)',
      'User canceled the biometric prompt',
      'The operation couldn\'t be completed. (OSStatus error -25300.)',
      'Keychain is locked',
    ];

    for (final message in unrelatedFailures) {
      test('rethrows and keeps the data on: $message', () async {
        when(() => storage.read(key: any(named: 'key')))
            .thenThrow(Exception(message));

        await expectLater(
          service.read('apix_access_token'),
          throwsA(isA<Exception>()),
        );

        verifyNever(() => storage.delete(key: any(named: 'key')));
        verifyNever(() => storage.deleteAll());
      });
    }

    test('a cancelled biometric prompt must not log the user out', () async {
      // The case worth naming: a user who declines Face ID once would come
      // back to a wiped session, which looks exactly like an expired token and
      // would be reported — if at all — as a server problem.
      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(Exception('Authentication canceled by the user'));

      await expectLater(
        service.read('apix_refresh_token'),
        throwsA(isA<Exception>()),
      );
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });
  });

  group('containsKey — same recovery, same restraint', () {
    test('reports absent and purges the key on corruption', () async {
      when(() => storage.containsKey(key: any(named: 'key')))
          .thenThrow(Exception('BadPaddingException'));

      expect(await service.containsKey('apix_access_token'), isFalse);
      verify(() => storage.delete(key: 'apix_access_token')).called(1);
    });

    test('rethrows anything else', () async {
      when(() => storage.containsKey(key: any(named: 'key')))
          .thenThrow(Exception('PlatformException'));

      await expectLater(
        service.containsKey('apix_access_token'),
        throwsA(isA<Exception>()),
      );
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });
  });

  group('readAll — the most destructive path in the package', () {
    test('wipes the whole store on corruption, and returns empty', () async {
      when(() => storage.readAll()).thenThrow(Exception('BadPaddingException'));

      expect(await service.readAll(), isEmpty);
      verify(() => storage.deleteAll()).called(1);
    });

    test('wipes nothing on an unrelated failure', () async {
      when(() => storage.readAll())
          .thenThrow(Exception('MissingPluginException'));

      await expectLater(service.readAll(), throwsA(isA<Exception>()));

      verifyNever(() => storage.deleteAll());
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });
  });

  group('the deletion announces itself before it happens', () {
    late List<SecureStorageRecovery> announced;
    late SecureStorageService watched;

    setUp(() {
      announced = [];
      watched = SecureStorageService(
        storage: storage,
        onBeforeRecoveryDelete: announced.add,
      );
    });

    test('a single-key purge is announced with its key', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(Exception('BadPaddingException'));

      await watched.read('apix_access_token');

      expect(announced, hasLength(1));
      expect(announced.single.operation, SecureStorageOperation.read);
      expect(announced.single.key, 'apix_access_token');
      expect(announced.single.isFullWipe, isFalse);
      expect(
        announced.single.error.toString(),
        contains('BadPaddingException'),
        reason: 'the message that triggered the decision is the contract of '
            'this component, so it has to travel with the event',
      );
    });

    test('a full wipe is announced as one, with no key', () async {
      when(() => storage.readAll()).thenThrow(Exception('bad_decrypt'));

      await watched.readAll();

      expect(announced.single.operation, SecureStorageOperation.readAll);
      expect(announced.single.key, isNull);
      expect(announced.single.isFullWipe, isTrue,
          reason: 'a consumer must be able to tell one lost key from a lost '
              'session without parsing anything');
    });

    test('containsKey announces too', () async {
      when(() => storage.containsKey(key: any(named: 'key')))
          .thenThrow(Exception('pad block corrupted'));

      await watched.containsKey('apix_refresh_token');

      expect(announced.single.operation, SecureStorageOperation.containsKey);
    });

    test('it fires BEFORE the deletion, not after', () async {
      final order = <String>[];
      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(Exception('BadPaddingException'));
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async => order.add('deleted'));

      final service = SecureStorageService(
        storage: storage,
        onBeforeRecoveryDelete: (_) => order.add('announced'),
      );
      await service.read('apix_access_token');

      expect(order, ['announced', 'deleted'],
          reason: 'a consumer that wants to snapshot what is about to go needs '
              'the moment where it still exists');
    });

    // The direction that matters most: this channel exists to make a false
    // positive visible, so it must stay silent when there is no purge.
    test('nothing is announced when nothing is deleted', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'token');
      await watched.read('apix_access_token');

      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(Exception('PlatformException'));
      await expectLater(
        watched.read('apix_access_token'),
        throwsA(isA<Exception>()),
      );

      expect(announced, isEmpty,
          reason: 'a channel that fires on the happy path is noise, and noise '
              'is how a real report gets ignored');
    });

    test('a handler that throws does not stop the recovery', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(Exception('BadPaddingException'));

      final service = SecureStorageService(
        storage: storage,
        onBeforeRecoveryDelete: (_) => throw StateError('consumer bug'),
      );

      expect(await service.read('apix_access_token'), isNull);
      verify(() => storage.delete(key: 'apix_access_token')).called(1);
    });

    test('no handler is still a valid configuration', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(Exception('BadPaddingException'));

      expect(await service.read('apix_access_token'), isNull);
    });
  });

  group('the happy paths still work', () {
    test('a normal read returns its value and deletes nothing', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'token');

      expect(await service.read('apix_access_token'), 'token');
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });

    test('an absent key is a miss, not a purge', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      expect(await service.read('apix_access_token'), isNull);
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });
  });
}
