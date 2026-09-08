import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A wrapper service for [FlutterSecureStorage] providing simplified
/// secure key-value storage operations.
///
/// This service abstracts the underlying secure storage implementation,
/// allowing for easy injection and testing.
///
/// Example usage:
/// ```dart
/// final storage = SecureStorageService();
///
/// // Store a value
/// await storage.write('api_key', 'my-secret-key');
///
/// // Read a value
/// final apiKey = await storage.read('api_key');
///
/// // Delete a value
/// await storage.delete('api_key');
///
/// // Clear all values
/// await storage.deleteAll();
/// ```
///
/// You can also inject a custom [FlutterSecureStorage] instance:
/// ```dart
/// final customStorage = FlutterSecureStorage(
///   iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
/// );
/// final storage = SecureStorageService(storage: customStorage);
/// ```
class SecureStorageService {
  final FlutterSecureStorage _storage;

  /// Called just **before** this service deletes anything to recover from
  /// unreadable data.
  ///
  /// The one place in apix that destroys a user's credentials without being
  /// asked to. It does so on purpose — encrypted bytes that cannot be decrypted
  /// will never become readable, and re-reading them forever is worse — but the
  /// decision rests on matching substrings against an exception's `toString()`,
  /// and a false positive does not degrade a feature: it **logs a user out**,
  /// indistinguishably from a session that expired on its own.
  ///
  /// Nothing else can report that. There is no exception left to catch (the
  /// recovery swallows it), no log, and the next read simply misses. A consumer
  /// asked for this channel first, ahead of the tests, for exactly that reason:
  /// their support desk receives "it logged me out" and has no way to connect
  /// it to a string in a platform message.
  ///
  /// ```dart
  /// SecureStorageService(
  ///   onBeforeRecoveryDelete: (event) => Sentry.captureMessage(
  ///     'secure storage purge: ${event.operation} ${event.key ?? "(all)"}',
  ///     level: SentryLevel.warning,
  ///   ),
  /// );
  /// ```
  ///
  /// Guarded like every consumer callback: a handler that throws cannot stop
  /// the recovery it was only meant to observe.
  ///
  /// It announces an **imminent attempt**, not an accomplished fact — the
  /// price of firing before, which is the moment a consumer needs to snapshot
  /// what is about to go. If the deletion then fails, the original error is
  /// rethrown rather than the one the cleanup raised, and the call answers
  /// nothing. That gap is narrow by construction: the failures where a
  /// deletion cannot run are classified [SecureStorageFailure.storeUnusable]
  /// and never enter the recovery in the first place.
  final void Function(SecureStorageRecovery event)? onBeforeRecoveryDelete;

  /// Creates a [SecureStorageService] with optional custom storage.
  ///
  /// If no [storage] is provided, a default [FlutterSecureStorage] is created
  /// with secure defaults (RSA OAEP + AES-GCM on Android).
  /// On iOS, the accessibility is set to `KeychainAccessibility.first_unlock`
  /// to ensure the data is accessible only when the device is unlocked.
  ///
  /// ## Why `resetOnError: false`, against the plugin's own default
  ///
  /// `AndroidOptions` defaults to `resetOnError: true`, and under that default
  /// the Android plugin handles unreadable data **itself**: it deletes the
  /// entry and retries the read, so nothing reaches the `catch` blocks below.
  /// The read still answers `null`, which is the right answer — but it answers
  /// it after destroying a credential that nobody was told about, and
  /// [onBeforeRecoveryDelete] never fires. A channel that exists to report the
  /// one place apix destroys data cannot be silent in the configuration
  /// everybody gets.
  ///
  /// The same default has a second effect, measured on an Android 16 emulator:
  /// when the plugin is left in a broken state (see
  /// [SecureStorageService.withBiometrics]), `resetOnError: true` turns a failed
  /// write into `deleteAll()` **reported as a success**. With it off, that
  /// surfaces as an exception instead of silently emptying the store.
  ///
  /// The trade-off, stated plainly: the plugin no longer repairs itself when its
  /// own initialisation fails — a failed migration after an algorithm change now
  /// raises instead of resetting. Pass your own [FlutterSecureStorage] with
  /// `resetOnError: true` if you prefer the old behaviour.
  ///
  /// ## ⚠️ From plugin 10.2.0, this option is only yours if apix asks first
  ///
  /// From **10.2.0** — this said 10.3.0 until it was read again, and a consumer
  /// on 10.2.x would have concluded they were safe — the Android plugin keeps
  /// one instance per preferences store
  /// (`FlutterSecureStoragePlugin.getOrCreateStorage`), and binds that store's
  /// options on the **first call for it**: `initialize` returns early on an
  /// already-initialised store *before* re-reading the config. Later
  /// callers naming the same store are served the first one's settings, in
  /// silence. This service names no store, so it uses the default one. If
  /// anything else in your app reaches `flutter_secure_storage` on that same
  /// default store before this service does, it is that call's `resetOnError`
  /// that applies, and the channel above goes quiet again. Give your own
  /// storage a `sharedPreferencesName` to keep the two apart — except when the
  /// other storage exists to **purge this one**, which has to share the store
  /// to reach anything. See [SecureStorageFailure.storeUnusable] for what that
  /// costs and what to do about it.
  ///
  /// At the declared floor (10.0.0) the config is re-read on every call, so this
  /// cannot happen — only the cipher is cached there.
  ///
  /// Measured against **both bounds** by the device probes in
  /// `apix_example_app/integration_test/`, which stage a real decryption failure
  /// rather than a mocked one: `secure_storage_device_test.dart` for this
  /// default, and `secure_storage_reset_on_error_device_test.dart` for what it
  /// costs to give it up.
  SecureStorageService({
    FlutterSecureStorage? storage,
    this.onBeforeRecoveryDelete,
  }) : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: false),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  /// Creates a [SecureStorageService] with biometric protection.
  ///
  /// On iOS, uses `KeychainAccessibility.passcode` with the `userPresence`
  /// flag. On Android, biometric-backed encryption (API 28+) with
  /// `enforceBiometrics: true`.
  ///
  /// **Flow:**
  /// 1. User logs in → tokens stored securely
  /// 2. User enables biometrics → protects access to storage
  /// 3. On app resume → biometric prompt → access to refreshToken
  ///
  /// ## ⚠️ On a device with nothing to prompt for, it **refuses**
  ///
  /// Measured on an Android 16 emulator with no lock screen and no enrolled
  /// biometric: the first storage call raises
  ///
  /// ```text
  /// BIOMETRIC_UNAVAILABLE: Biometric enforcement enabled but device has no
  /// PIN, pattern, password, or biometric enrolled. Cannot generate secure key.
  /// ```
  ///
  /// ⚠️ That is the message on the **first** run against a virgin store. From
  /// the second onward the store carries algorithm markers, so the refusal
  /// arrives wrapped — `Migration failed after algorithm change (Algorithm
  /// changed detected). Enable resetOnError=true or call deleteAll().`, with
  /// `BIOMETRIC_UNAVAILABLE` down in the `Caused by:` chain. Measured on an
  /// Android 11 (API 30) emulator; pinned by the device probe, which matches
  /// the buried token rather than the outer message for exactly this reason.
  /// A consumer keying on the bare string sees it once and never again.
  /// [SecureStorageService.classify] calls the wrapped form
  /// [SecureStorageFailure.storeUnusable], which is what it is.
  ///
  /// That is `enforceBiometrics: true` doing its job. Decide what your app does
  /// about it — send the user to secure their device, or fall back to the plain
  /// constructor knowing what you are giving up — but decide, because the state
  /// the plugin is left in afterwards is worse than the refusal.
  ///
  /// ## ⚠️ Do not catch that refusal and keep writing
  ///
  /// The Android plugin assigns its preferences field **before** the cipher it
  /// failed to build, so every later call in the process short-circuits
  /// initialisation and finds no cipher. Measured, and confirmed in logcat:
  ///
  /// ```text
  /// NullPointerException: StorageCipher.encrypt(byte[]) on a null object
  ///   at FlutterSecureStorage.writeUnsafe(:130)
  ///   at FlutterSecureStorage.initialize(:151)   ← the cached early return
  /// ```
  ///
  /// Under the plugin's own `resetOnError: true` that failure becomes
  /// `deleteAll()` **reported to Dart as a success** — an app that swallows the
  /// refusal and carries on empties its entire secure store while believing it
  /// wrote. apix passes `resetOnError: false` precisely so this surfaces as an
  /// exception instead. Restarting the process is what clears the broken state.
  ///
  /// Where the guarantee matters, check the device state yourself first —
  /// `local_auth`'s `canCheckBiometrics` / `isDeviceSupported` — rather than
  /// discovering it from a thrown write.
  ///
  /// Pinned by `apix_example_app/integration_test/
  /// secure_storage_biometric_device_test.dart`, which is where those
  /// measurements come from. It lives in a file of its own because one process
  /// gets one plugin initialisation, and a biometric probe sharing a file with
  /// other storage calls measures somebody else's cipher.
  ///
  /// Example:
  /// ```dart
  /// final storage = SecureStorageService.withBiometrics();
  /// final tokenProvider = SecureTokenProvider(storage: storage);
  /// ```
  factory SecureStorageService.withBiometrics({
    String biometricPromptTitle = 'Authentication required',
    String biometricPromptSubtitle = 'Authenticate to access your account',
    void Function(SecureStorageRecovery event)? onBeforeRecoveryDelete,
  }) {
    return SecureStorageService(
      onBeforeRecoveryDelete: onBeforeRecoveryDelete,
      storage: FlutterSecureStorage(
        aOptions: AndroidOptions.biometric(
          enforceBiometrics: true,
          resetOnError: false,
          biometricPromptTitle: biometricPromptTitle,
          biometricPromptSubtitle: biometricPromptSubtitle,
        ),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.userPresence],
        ),
      ),
    );
  }

  /// Writes a [value] for the given [key] to secure storage.
  ///
  /// If a value already exists for the key, it will be overwritten.
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// Reads the value for the given [key] from secure storage.
  ///
  /// Returns `null` if no value exists for the key.
  ///
  /// On [SecureStorageFailure.unreadableEntry] — the entry's bytes no longer
  /// decrypt — only the affected key is deleted, never the whole store, and
  /// the miss is reported as `null`. Every other failure is rethrown,
  /// [SecureStorageFailure.storeUnusable] included: there is nothing a
  /// deletion could reach there, and answering `null` would claim an empty
  /// store rather than an unreachable one.
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      if (classify(e) == SecureStorageFailure.unreadableEntry) {
        _announce(SecureStorageOperation.read, e, key: key);
        if (!await _recoveryDeleteSucceeded(() => delete(key))) rethrow;
        return null;
      }
      rethrow;
    }
  }

  /// Hands a pending recovery deletion to [onBeforeRecoveryDelete].
  ///
  /// Before, never after: a consumer that wants to snapshot what is about to
  /// go needs the moment where it still exists.
  void _announce(
    SecureStorageOperation operation,
    Object error, {
    String? key,
  }) {
    final handler = onBeforeRecoveryDelete;
    if (handler == null) return;
    try {
      handler(SecureStorageRecovery(
        operation: operation,
        key: key,
        error: error,
      ));
    } catch (_) {
      // Observation must never break the recovery it observes.
    }
  }

  /// What kind of failure [error] is, as far as this service can tell.
  ///
  /// Public because the two failures below need **opposite** reactions from a
  /// consumer and nothing else separates them: `flutter_secure_storage` reports
  /// every platform failure as a `PlatformException` with the same
  /// `code: 'Exception encountered'`, so the only discriminator is a substring
  /// of the message. Doing that matching in your own code is what this exists
  /// to spare you — and it is matching this service has to do anyway, since it
  /// is what decides whether a credential gets deleted.
  ///
  /// ```dart
  /// try {
  ///   token = await storage.read('apix_access_token');
  /// } catch (e) {
  ///   if (SecureStorageService.classify(e) ==
  ///       SecureStorageFailure.storeUnusable) {
  ///     // Nothing to purge — see the enum value for what to do instead.
  ///   }
  ///   rethrow;
  /// }
  /// ```
  ///
  /// Never throws, whatever it is handed.
  static SecureStorageFailure classify(Object error) {
    final message = error.toString().toLowerCase();

    // First, and it has to be first: the Android plugin wraps the cause of a
    // cipher-initialisation failure inside a message that can itself carry
    // 'Bad padding' — `Key mismatch after algorithm change (Bad padding, wrong
    // key for cipher algorithm)`. Tested after the substrings below, that one
    // reads as a corrupted entry and takes a deletion that cannot run.
    for (final marker in _storeUnusableMarkers) {
      if (message.contains(marker)) return SecureStorageFailure.storeUnusable;
    }

    for (final marker in _unreadableEntryMarkers) {
      if (message.contains(marker)) return SecureStorageFailure.unreadableEntry;
    }

    return SecureStorageFailure.other;
  }

  /// The store's own key is unusable — every call through the plugin fails.
  ///
  /// Verbatim `String.format` templates and messages from
  /// `flutter_secure_storage`, read in its Android sources at **10.0.0, 10.2.0
  /// and 10.3.1** (2026-09-08) and identical across the three — which is the
  /// whole range this package declares.
  static const _storeUnusableMarkers = [
    // FlutterSecureStorage.handleKeyMismatch, both branches.
    'key mismatch after algorithm change',
    'migration failed after algorithm change',
    // initializeStorageCipher, NoSuchAlgorithmException.
    'required cryptographic algorithm not supported by device',
    // initialize, legacy EncryptedSharedPreferences data with migration off.
    'encryptedsharedpreferences data found but migration is disabled',
  ];

  /// One entry's bytes cannot be decrypted; the store itself is fine.
  ///
  /// `bad_decrypt` and `error:1e000065` are the two that a real corruption
  /// produced on an Android 16 emulator, measured through the device probes in
  /// `apix_example_app/integration_test/`:
  /// `javax.crypto.AEADBadTagException: error:1e000065:…:BAD_DECRYPT`.
  ///
  /// The `IllegalBlockSizeException` family is here for parity, not from a
  /// measurement: `Cipher.doFinal` raises it as the sibling of
  /// `BadPaddingException` for the same reason — a payload that does not
  /// decrypt — on the AES-CBC storage cipher, which is what the plugin falls
  /// back to below API 23 and what a consumer gets by choosing
  /// `StorageCipherAlgorithm.AES_CBC_PKCS7Padding`. Recognising one of a pair
  /// and not the other is the asymmetry, not the fix.
  static const _unreadableEntryMarkers = [
    'bad padding',
    'badpaddingexception',
    'pad block corrupted',
    'bad_decrypt',
    'error:1e000065',
    'illegalblocksizeexception',
    'wrong_final_block_length',
    'error:1e00007b',
  ];

  /// Runs a recovery deletion, and says whether it actually happened.
  ///
  /// A deletion can fail for the same reason the read did, and then there is
  /// nothing to recover: see [SecureStorageFailure.storeUnusable]. The caller
  /// rethrows the original in that case — the failure that names the cause,
  /// rather than the one raised by the cleanup.
  Future<bool> _recoveryDeleteSucceeded(
      Future<void> Function() deletion) async {
    try {
      await deletion();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the value for the given [key] from secure storage.
  ///
  /// Does nothing if no value exists for the key.
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  /// Deletes all values from secure storage.
  ///
  /// Use with caution as this removes all stored data.
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  /// Checks if a value exists for the given [key].
  ///
  /// Returns `true` if a value exists, `false` otherwise.
  ///
  /// Same recovery as [read]: an [SecureStorageFailure.unreadableEntry] drops
  /// the affected key and answers `false`; anything else is rethrown.
  Future<bool> containsKey(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      if (classify(e) == SecureStorageFailure.unreadableEntry) {
        _announce(SecureStorageOperation.containsKey, e, key: key);
        if (!await _recoveryDeleteSucceeded(() => delete(key))) rethrow;
        return false;
      }
      rethrow;
    }
  }

  /// Reads all key-value pairs from secure storage.
  ///
  /// Returns an empty map if no values exist.
  ///
  /// The most destructive path in this package: an
  /// [SecureStorageFailure.unreadableEntry] here clears **the whole store**,
  /// because there is no single key to blame. Anything else is rethrown.
  Future<Map<String, String>> readAll() async {
    try {
      return await _storage.readAll();
    } catch (e) {
      if (classify(e) == SecureStorageFailure.unreadableEntry) {
        // No key: this one takes the whole store.
        _announce(SecureStorageOperation.readAll, e);
        if (!await _recoveryDeleteSucceeded(deleteAll)) rethrow;
        return {};
      }
      rethrow;
    }
  }
}

/// What kind of failure a secure-storage call ran into.
///
/// Returned by [SecureStorageService.classify]. The two named values need
/// opposite reactions, which is the whole reason this is public.
enum SecureStorageFailure {
  /// One entry's bytes cannot be decrypted. The store itself is healthy.
  ///
  /// The entry will never become readable again, so dropping it *is* the
  /// recovery — and [SecureStorageService] performs it for you: `read` answers
  /// `null`, `containsKey` answers `false`, `readAll` answers `{}`, after
  /// announcing the deletion on
  /// [SecureStorageService.onBeforeRecoveryDelete]. You only see this value if
  /// you classify an error you caught from somewhere else.
  unreadableEntry,

  /// The store's own key is unusable, so **nothing** in it can be read,
  /// written or deleted through the plugin — including the deletion that would
  /// "repair" it.
  ///
  /// [SecureStorageService] never deletes on this, and never answers `null`:
  /// it rethrows, because there is no state it could put you in that would be
  /// truthful. What to do is yours to decide, and the two useful moves are:
  ///
  /// * **retry once.** Read in the Android plugin's sources (10.0.0 · 10.2.0 ·
  ///   10.3.1, on 2026-09-08), not measured here: when the failure comes from
  ///   *missing* algorithm markers — the state a "clear app data" leaves behind
  ///   when the Keystore key outlives the preferences — `StorageCipherFactory`
  ///   writes the current markers as it builds, so the **next** call no longer
  ///   takes that branch. The failure clears itself, and one retry is enough.
  /// * **treat a second failure as permanent.** When the markers are present
  ///   but name another algorithm, nothing is rewritten and every call fails
  ///   identically until the store is reset — pass your own
  ///   `FlutterSecureStorage` with `resetOnError: true`, which is the plugin's
  ///   own recovery for this, knowing what [SecureStorageService] gives up by
  ///   disabling it (see the constructor).
  ///
  /// ⚠️ **One envelope, several causes.** `Migration failed after algorithm
  /// change (Algorithm changed detected)` is what a `withBiometrics()` refusal
  /// looks like from its second run onward — measured on an Android 11 (API 30)
  /// emulator with no lock screen, `BIOMETRIC_UNAVAILABLE` buried in the
  /// `Caused by:` chain. A retry never clears that one: the device has nothing
  /// to prompt for. The `(%s)` does not tell the causes apart; the
  /// `Caused by:` chain does, and it travels in
  /// [SecureStorageRecovery.error] and in the exception you catch.
  ///
  /// ⚠️ That purge instance has to name the **same** store to reach anything,
  /// and from plugin 10.2.0 the first successful call for a store fixes its
  /// options for the process. So its `resetOnError: true` governs apix's calls
  /// afterwards too: [SecureStorageService.onBeforeRecoveryDelete] goes quiet,
  /// and a write that fails after a broken initialisation comes back as a
  /// success. Restart the process after purging rather than carrying on inside
  /// it — the same advice as [SecureStorageService.withBiometrics].
  ///
  /// Do not catch this and keep writing: see
  /// [SecureStorageService.withBiometrics] for what a plugin left without a
  /// cipher does to the next write.
  storeUnusable,

  /// Anything else — a cancelled biometric prompt, a locked keychain, a
  /// missing plugin, a network or parsing failure that happened to travel
  /// through here. Rethrown untouched, and never a reason to delete anything.
  other,
}

/// Which read triggered a recovery deletion.
enum SecureStorageOperation {
  /// A single-key read. The affected key is dropped.
  read,

  /// An existence check. The affected key is dropped.
  containsKey,

  /// A full read. **The entire store is dropped**, so
  /// [SecureStorageRecovery.key] is null.
  readAll,
}

/// A deletion [SecureStorageService] is about to perform to recover from data
/// it cannot decrypt.
class SecureStorageRecovery {
  /// Which read hit the unreadable data.
  final SecureStorageOperation operation;

  /// The key about to be deleted, or null when the whole store is.
  final String? key;

  /// The platform exception whose message triggered the decision.
  ///
  /// Worth capturing verbatim: the recognised substrings are the real contract
  /// of this component, and a message that *nearly* matches is the shape a
  /// future false positive will take.
  final Object error;

  /// Whether this event is about to clear everything rather than one key.
  bool get isFullWipe => operation == SecureStorageOperation.readAll;

  /// Creates a [SecureStorageRecovery].
  const SecureStorageRecovery({
    required this.operation,
    required this.error,
    this.key,
  });

  @override
  String toString() => 'SecureStorageRecovery(${operation.name}'
      '${key == null ? ', whole store' : ' $key'}): $error';
}
