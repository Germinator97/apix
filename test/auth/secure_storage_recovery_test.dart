import 'package:apix/src/auth/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

/// Every message the Android plugin sends when the store's own key is unusable.
///
/// Verbatim from its sources, identical at 10.0.0, 10.2.0 and 10.3.1 — the
/// range this package declares. Named here rather than inline so a list literal
/// of wrapped strings cannot hide a missing comma.
const deadStoreMessages = [
  'Key mismatch after algorithm change (Algorithm changed detected). Enable migrateOnAlgorithmChange=true to preserve data, or resetOnError=true to delete.',
  'Key mismatch after algorithm change (Invalid key, key type incompatible with cipher). Enable migrateOnAlgorithmChange=true to preserve data, or resetOnError=true to delete.',
  'Migration failed after algorithm change (Illegal block size, wrong cipher configuration). Enable resetOnError=true or call deleteAll().',
  'Required cryptographic algorithm not supported by device.',
  'EncryptedSharedPreferences data found but migration is disabled. Set migrateOnAlgorithmChange=true to migrate.',
];

/// The biometric refusal measured on an Android 16 emulator (pass 4).
///
/// It leaves the plugin without a cipher for the rest of the process, but it is
/// not a classification this service acts on: it must stay `other`.
const biometricUnavailable =
    'BIOMETRIC_UNAVAILABLE: Biometric enforcement enabled but device has no PIN, pattern, password, or biometric enrolled.';

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

  /// The plugin has two failure classes wearing one exception type, and they
  /// need opposite reactions. `initialize()` failing means the store's key is
  /// unusable, and — this is the part that is easy to miss — the Android plugin
  /// runs *every* method inside that `initialize`'s success callback, deletion
  /// included. So the recovery this service performs cannot run there. Worse,
  /// the plugin wraps the cause in a message that can itself carry
  /// `Bad padding`, which is how the narrow, correct matcher below reached into
  /// a class it must not touch.
  group('classify — the two classes, and the order that separates them', () {
    // Verbatim from a consumer's device: Android API 30, plugin 10.3.1,
    // app data cleared while the Keystore key outlived it.
    const reported = 'PlatformException(Exception encountered, '
        'Migration failed after algorithm change (Algorithm changed detected). '
        'Enable resetOnError=true or call deleteAll()., '
        'java.lang.Exception: Migration failed after algorithm change '
        '(Algorithm changed detected). Enable resetOnError=true or call '
        'deleteAll().\n'
        '\tat com.it_nomads.fluttersecurestorage.FlutterSecureStorage'
        '.handleKeyMismatch(FlutterSecureStorage.java:964)\n'
        'Caused by: javax.crypto.IllegalBlockSizeException: '
        'error:1e00007b:Cipher functions:OPENSSL_internal:'
        'WRONG_FINAL_BLOCK_LENGTH\n, null)';

    test('the message a consumer actually captured is storeUnusable', () {
      expect(
        SecureStorageService.classify(Exception(reported)),
        SecureStorageFailure.storeUnusable,
        reason: 'the store cannot be read, written OR deleted through the '
            'plugin here — answering null would claim an empty store rather '
            'than an unreachable one',
      );
    });

    // Same envelope, same `(%s)`, a completely different cause — and this one
    // is produced by apix's own `withBiometrics()` on a device with no lock
    // screen, from its second run onward. Captured verbatim on an Android 11
    // (API 30) emulator by
    // `apix_example_app/integration_test/secure_storage_biometric_device_test`.
    //
    // It matters twice: `storeUnusable` is the right answer (the store really
    // is unusable), and it is the counter-example to "retry once" — no retry
    // will ever give that device something to prompt for.
    test(
        'a biometric refusal wrapped in the migration envelope is storeUnusable',
        () {
      const measured =
          'PlatformException(Exception encountered, Migration failed after algorithm change (Algorithm changed detected). Enable resetOnError=true or call deleteAll()., java.lang.Exception: Migration failed after algorithm change (Algorithm changed detected). Enable resetOnError=true or call deleteAll().\n'
          'Caused by: java.lang.Exception: Non-biometric migration failed\n'
          'Caused by: java.lang.Exception: BIOMETRIC_UNAVAILABLE: Biometric enforcement enabled but device has no PIN, pattern, password, or biometric enrolled. Cannot generate secure key.\n, null)';

      expect(
        SecureStorageService.classify(Exception(measured)),
        SecureStorageFailure.storeUnusable,
      );
    });

    // And the bare form, which is what the FIRST run against a virgin store
    // raises. It is not a store failure yet — it is the refusal itself, and
    // apix rethrows it either way. The pair is what shows the envelope is what
    // moves the classification, not the words BIOMETRIC_UNAVAILABLE.
    test('the bare refusal, on the other hand, is other', () {
      expect(SecureStorageService.classify(Exception(biometricUnavailable)),
          SecureStorageFailure.other);
    });

    // The whole reason the store-unusable markers are tested first. This
    // message carries `Bad padding` inside its parentheses, so a matcher that
    // looks for corruption first classifies a dead store as a dead entry and
    // takes a deletion that cannot run.
    test('a key-mismatch envelope that CONTAINS "Bad padding" is not an entry',
        () {
      expect(
        SecureStorageService.classify(Exception(
          'Key mismatch after algorithm change (Bad padding, wrong key for '
          'cipher algorithm). Enable migrateOnAlgorithmChange=true to preserve '
          'data, or resetOnError=true to delete.',
        )),
        SecureStorageFailure.storeUnusable,
        reason: 'order matters: the envelope has to be recognised before the '
            'substring it contains',
      );
    });

    for (final message in deadStoreMessages) {
      test('storeUnusable on: ${message.substring(0, 40)}…', () {
        expect(SecureStorageService.classify(Exception(message)),
            SecureStorageFailure.storeUnusable);
      });
    }

    // The other half. A matcher that answers `storeUnusable` to everything
    // would pass every test above and quietly stop recovering anything.
    for (final message in corruptionMessages) {
      test('still unreadableEntry on: $message', () {
        expect(SecureStorageService.classify(Exception(message)),
            SecureStorageFailure.unreadableEntry);
      });
    }

    // Added with this change, and not from a measurement — `doFinal` raises
    // IllegalBlockSizeException as the sibling of BadPaddingException on the
    // AES-CBC storage cipher, and recognising one of a pair and not the other
    // is the asymmetry. Outside any store-unusable envelope, it is an entry.
    test('a bare IllegalBlockSizeException is an unreadable entry', () {
      expect(
        SecureStorageService.classify(Exception(
          'javax.crypto.IllegalBlockSizeException: error:1e00007b:Cipher '
          'functions:OPENSSL_internal:WRONG_FINAL_BLOCK_LENGTH',
        )),
        SecureStorageFailure.unreadableEntry,
      );
    });

    for (final message in const [
      'SocketException: Failed host lookup: api.example.com',
      'TimeoutException after 0:00:30.000000',
      'FormatException: Unexpected character',
      'Object/factory with type ApiClient is not registered',
      '',
      'Unknown error',
      'Authentication canceled by the user',
      biometricUnavailable,
      'MissingPluginException(No implementation found for method read)',
      'Code: -25308, Message: User interaction is not allowed.',
    ]) {
      test('other on: ${message.isEmpty ? '(message vide)' : message}', () {
        expect(SecureStorageService.classify(Exception(message)),
            SecureStorageFailure.other);
      });
    }

    test('never throws, whatever it is handed', () {
      for (final input in <Object>[
        'a bare string',
        42,
        Exception(),
        StateError('boom'),
        Object(),
      ]) {
        expect(() => SecureStorageService.classify(input), returnsNormally);
      }
    });
  });

  group('a dead store is rethrown, never purged', () {
    late List<SecureStorageRecovery> announced;
    late SecureStorageService watched;
    final dead = Exception(
      'Migration failed after algorithm change (Algorithm changed detected). '
      'Enable resetOnError=true or call deleteAll().',
    );

    setUp(() {
      announced = [];
      watched = SecureStorageService(
        storage: storage,
        onBeforeRecoveryDelete: announced.add,
      );
    });

    test('read rethrows and deletes nothing', () async {
      when(() => storage.read(key: any(named: 'key'))).thenThrow(dead);

      await expectLater(
          watched.read('apix_access_token'), throwsA(isA<Exception>()));

      verifyNever(() => storage.delete(key: any(named: 'key')));
      verifyNever(() => storage.deleteAll());
      expect(announced, isEmpty,
          reason: 'nothing was destroyed, so nothing may be reported as such');
    });

    test('containsKey rethrows and deletes nothing', () async {
      when(() => storage.containsKey(key: any(named: 'key'))).thenThrow(dead);

      await expectLater(
          watched.containsKey('apix_access_token'), throwsA(isA<Exception>()));

      verifyNever(() => storage.delete(key: any(named: 'key')));
      expect(announced, isEmpty);
    });

    test('readAll does not wipe the store it cannot reach', () async {
      when(() => storage.readAll()).thenThrow(dead);

      await expectLater(watched.readAll(), throwsA(isA<Exception>()));

      verifyNever(() => storage.deleteAll());
      expect(announced, isEmpty);
    });
  });

  /// The belt for everything the classification does not catch. A deletion can
  /// fail for the same reason the read did; when it does, the caller has to see
  /// the failure that names the cause, not the one raised by the cleanup.
  group('when the recovery deletion itself fails', () {
    late List<SecureStorageRecovery> announced;
    late SecureStorageService watched;
    final original = Exception('BadPaddingException: the original');
    final fromCleanup = Exception('BadPaddingException: raised by the cleanup');

    setUp(() {
      announced = [];
      watched = SecureStorageService(
        storage: storage,
        onBeforeRecoveryDelete: announced.add,
      );
    });

    test('read rethrows the ORIGINAL, not the deletion failure', () async {
      when(() => storage.read(key: any(named: 'key'))).thenThrow(original);
      when(() => storage.delete(key: any(named: 'key'))).thenThrow(fromCleanup);

      await expectLater(
        watched.read('apix_access_token'),
        throwsA(predicate<Object>(
          (e) => e.toString().contains('the original'),
          'the original failure, not the cleanup\'s',
        )),
      );
    });

    test('readAll rethrows the ORIGINAL, not the deleteAll failure', () async {
      when(() => storage.readAll()).thenThrow(original);
      when(() => storage.deleteAll()).thenThrow(fromCleanup);

      await expectLater(
        watched.readAll(),
        throwsA(predicate<Object>(
          (e) => e.toString().contains('the original'),
          'the original failure, not the cleanup\'s',
        )),
      );
    });

    test('the announcement already went out — it names an attempt', () async {
      when(() => storage.read(key: any(named: 'key'))).thenThrow(original);
      when(() => storage.delete(key: any(named: 'key'))).thenThrow(fromCleanup);

      await expectLater(
          watched.read('apix_access_token'), throwsA(isA<Exception>()));

      expect(announced, hasLength(1),
          reason: 'firing before the deletion is the documented contract; a '
              'consumer that snapshots what is about to go needs that moment. '
              'What it must not do is claim the deletion happened.');
    });

    // The other direction: a deletion that works must still answer, or this
    // guard would pass on a service that gave up on every recovery.
    test('a deletion that succeeds still answers null', () async {
      when(() => storage.read(key: any(named: 'key'))).thenThrow(original);
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});

      expect(await watched.read('apix_access_token'), isNull);
      verify(() => storage.delete(key: 'apix_access_token')).called(1);
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
