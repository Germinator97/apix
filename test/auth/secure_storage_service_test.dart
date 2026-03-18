import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apix/src/auth/secure_storage_service.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late SecureStorageService service;

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    service = SecureStorageService(storage: mockStorage);
  });

  group('SecureStorageService', () {
    group('write', () {
      test('should write value to storage', () async {
        when(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value')))
            .thenAnswer((_) async {});

        await service.write('test_key', 'test_value');

        verify(() => mockStorage.write(key: 'test_key', value: 'test_value')).called(1);
      });
    });

    group('read', () {
      test('should return value when key exists', () async {
        when(() => mockStorage.read(key: any(named: 'key')))
            .thenAnswer((_) async => 'stored_value');

        final result = await service.read('test_key');

        expect(result, 'stored_value');
        verify(() => mockStorage.read(key: 'test_key')).called(1);
      });

      test('should return null when key does not exist', () async {
        when(() => mockStorage.read(key: any(named: 'key')))
            .thenAnswer((_) async => null);

        final result = await service.read('nonexistent_key');

        expect(result, isNull);
      });
    });

    group('delete', () {
      test('should delete value from storage', () async {
        when(() => mockStorage.delete(key: any(named: 'key')))
            .thenAnswer((_) async {});

        await service.delete('test_key');

        verify(() => mockStorage.delete(key: 'test_key')).called(1);
      });
    });

    group('deleteAll', () {
      test('should delete all values from storage', () async {
        when(() => mockStorage.deleteAll()).thenAnswer((_) async {});

        await service.deleteAll();

        verify(() => mockStorage.deleteAll()).called(1);
      });
    });

    group('containsKey', () {
      test('should return true when key exists', () async {
        when(() => mockStorage.containsKey(key: any(named: 'key')))
            .thenAnswer((_) async => true);

        final result = await service.containsKey('test_key');

        expect(result, isTrue);
        verify(() => mockStorage.containsKey(key: 'test_key')).called(1);
      });

      test('should return false when key does not exist', () async {
        when(() => mockStorage.containsKey(key: any(named: 'key')))
            .thenAnswer((_) async => false);

        final result = await service.containsKey('nonexistent_key');

        expect(result, isFalse);
      });
    });

    group('readAll', () {
      test('should return all stored values', () async {
        when(() => mockStorage.readAll())
            .thenAnswer((_) async => {'key1': 'value1', 'key2': 'value2'});

        final result = await service.readAll();

        expect(result, {'key1': 'value1', 'key2': 'value2'});
        verify(() => mockStorage.readAll()).called(1);
      });

      test('should return empty map when no values exist', () async {
        when(() => mockStorage.readAll()).thenAnswer((_) async => {});

        final result = await service.readAll();

        expect(result, isEmpty);
      });
    });

    group('default constructor', () {
      test('should create service with default storage when none provided', () {
        final defaultService = SecureStorageService();

        expect(defaultService, isA<SecureStorageService>());
      });
    });
  });
}
