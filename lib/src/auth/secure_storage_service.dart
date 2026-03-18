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

  /// Creates a [SecureStorageService] with optional custom storage.
  ///
  /// If no [storage] is provided, a default [FlutterSecureStorage] is created
  /// with `AndroidOptions.encryptedSharedPreferences` set to `true` for
  /// better security on Android devices.
  /// On iOS, the accessibility is set to `KeychainAccessibility.first_unlock`
  /// to ensure the data is accessible only when the device is unlocked.
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  /// Writes a [value] for the given [key] to secure storage.
  ///
  /// If a value already exists for the key, it will be overwritten.
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// Reads the value for the given [key] from secure storage.
  ///
  /// Returns `null` if no value exists for the key.
  Future<String?> read(String key) async {
    return _storage.read(key: key);
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
  Future<bool> containsKey(String key) async {
    return _storage.containsKey(key: key);
  }

  /// Reads all key-value pairs from secure storage.
  ///
  /// Returns an empty map if no values exist.
  Future<Map<String, String>> readAll() async {
    return _storage.readAll();
  }
}
