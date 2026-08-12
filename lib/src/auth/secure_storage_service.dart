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
  /// recovery swallows it), no log, and the next read simply misses. a consumer
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
  /// ## ⚠️ On plugin 10.3+, this option is only yours if apix asks first
  ///
  /// From **10.3.0** the Android plugin keeps one instance per preferences
  /// store, and binds that store's options on the **first call for it** — later
  /// callers naming the same store are served the first one's settings, in
  /// silence. This service names no store, so it uses the default one. If
  /// anything else in your app reaches `flutter_secure_storage` on that same
  /// default store before this service does, it is that call's `resetOnError`
  /// that applies, and the channel above goes quiet again. Give your own
  /// storage a `sharedPreferencesName` to keep the two apart.
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
  /// If a bad padding exception occurs (corrupted data), only the affected
  /// key is deleted rather than clearing all storage.
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      if (_isBadPaddingException(e)) {
        _announce(SecureStorageOperation.read, e, key: key);
        await delete(key);
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

  /// Checks if the exception is a bad padding exception.
  ///
  /// This typically occurs when encrypted data is corrupted,
  /// e.g., after app reinstall or key rotation.
  bool _isBadPaddingException(Object e) {
    final message = e.toString().toLowerCase();
    return message.contains('bad padding') ||
        message.contains('badpaddingexception') ||
        message.contains('pad block corrupted') ||
        message.contains('bad_decrypt') ||
        message.contains('error:1e000065');
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
  /// If a bad padding exception occurs (corrupted data), only the affected
  /// key is deleted.
  Future<bool> containsKey(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      if (_isBadPaddingException(e)) {
        _announce(SecureStorageOperation.containsKey, e, key: key);
        await delete(key);
        return false;
      }
      rethrow;
    }
  }

  /// Reads all key-value pairs from secure storage.
  ///
  /// Returns an empty map if no values exist.
  /// If a bad padding exception occurs (corrupted data), the storage is cleared.
  Future<Map<String, String>> readAll() async {
    try {
      return await _storage.readAll();
    } catch (e) {
      if (_isBadPaddingException(e)) {
        // No key: this one takes the whole store.
        _announce(SecureStorageOperation.readAll, e);
        await deleteAll();
        return {};
      }
      rethrow;
    }
  }
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
