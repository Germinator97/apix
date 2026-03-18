import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apix/src/auth/secure_storage_service.dart';
import 'package:apix/src/auth/secure_token_provider.dart';
import 'package:apix/src/auth/token_provider.dart';

class MockSecureStorageService extends Mock implements SecureStorageService {}

void main() {
  late MockSecureStorageService mockStorage;
  late SecureTokenProvider provider;

  setUp(() {
    mockStorage = MockSecureStorageService();
    provider = SecureTokenProvider(storage: mockStorage);
  });

  group('SecureTokenProvider', () {
    group('implements TokenProvider', () {
      test('should implement TokenProvider interface', () {
        expect(provider, isA<TokenProvider>());
      });
    });

    group('getAccessToken', () {
      test('should read access token from storage with default key', () async {
        when(() => mockStorage.read('apix_access_token'))
            .thenAnswer((_) async => 'access_token_value');

        final result = await provider.getAccessToken();

        expect(result, 'access_token_value');
        verify(() => mockStorage.read('apix_access_token')).called(1);
      });

      test('should return null when no access token exists', () async {
        when(() => mockStorage.read('apix_access_token'))
            .thenAnswer((_) async => null);

        final result = await provider.getAccessToken();

        expect(result, isNull);
      });
    });

    group('getRefreshToken', () {
      test('should read refresh token from storage with default key', () async {
        when(() => mockStorage.read('apix_refresh_token'))
            .thenAnswer((_) async => 'refresh_token_value');

        final result = await provider.getRefreshToken();

        expect(result, 'refresh_token_value');
        verify(() => mockStorage.read('apix_refresh_token')).called(1);
      });

      test('should return null when no refresh token exists', () async {
        when(() => mockStorage.read('apix_refresh_token'))
            .thenAnswer((_) async => null);

        final result = await provider.getRefreshToken();

        expect(result, isNull);
      });
    });

    group('saveTokens', () {
      test('should write both tokens to storage', () async {
        when(() => mockStorage.write(any(), any())).thenAnswer((_) async {});

        await provider.saveTokens('new_access', 'new_refresh');

        verify(() => mockStorage.write('apix_access_token', 'new_access'))
            .called(1);
        verify(() => mockStorage.write('apix_refresh_token', 'new_refresh'))
            .called(1);
      });
    });

    group('clearTokens', () {
      test('should delete both tokens from storage', () async {
        when(() => mockStorage.delete(any())).thenAnswer((_) async {});

        await provider.clearTokens();

        verify(() => mockStorage.delete('apix_access_token')).called(1);
        verify(() => mockStorage.delete('apix_refresh_token')).called(1);
      });
    });

    group('custom keys', () {
      test('should use custom access token key', () async {
        final customProvider = SecureTokenProvider(
          storage: mockStorage,
          accessTokenKey: 'custom_access',
        );

        when(() => mockStorage.read('custom_access'))
            .thenAnswer((_) async => 'token');

        await customProvider.getAccessToken();

        verify(() => mockStorage.read('custom_access')).called(1);
      });

      test('should use custom refresh token key', () async {
        final customProvider = SecureTokenProvider(
          storage: mockStorage,
          refreshTokenKey: 'custom_refresh',
        );

        when(() => mockStorage.read('custom_refresh'))
            .thenAnswer((_) async => 'token');

        await customProvider.getRefreshToken();

        verify(() => mockStorage.read('custom_refresh')).called(1);
      });

      test('should use custom keys for saveTokens', () async {
        final customProvider = SecureTokenProvider(
          storage: mockStorage,
          accessTokenKey: 'custom_access',
          refreshTokenKey: 'custom_refresh',
        );

        when(() => mockStorage.write(any(), any())).thenAnswer((_) async {});

        await customProvider.saveTokens('access', 'refresh');

        verify(() => mockStorage.write('custom_access', 'access')).called(1);
        verify(() => mockStorage.write('custom_refresh', 'refresh')).called(1);
      });

      test('should use custom keys for clearTokens', () async {
        final customProvider = SecureTokenProvider(
          storage: mockStorage,
          accessTokenKey: 'custom_access',
          refreshTokenKey: 'custom_refresh',
        );

        when(() => mockStorage.delete(any())).thenAnswer((_) async {});

        await customProvider.clearTokens();

        verify(() => mockStorage.delete('custom_access')).called(1);
        verify(() => mockStorage.delete('custom_refresh')).called(1);
      });
    });

    group('storage getter', () {
      test('should expose storage for secondary usage', () {
        expect(provider.storage, same(mockStorage));
      });

      test('should allow using storage for other secrets', () async {
        when(() => mockStorage.write(any(), any())).thenAnswer((_) async {});
        when(() => mockStorage.read(any()))
            .thenAnswer((_) async => 'firebase_token_value');

        await provider.storage.write('firebase_token', 'my_firebase_token');
        final firebaseToken = await provider.storage.read('firebase_token');

        expect(firebaseToken, 'firebase_token_value');
        verify(() => mockStorage.write('firebase_token', 'my_firebase_token'))
            .called(1);
      });
    });

    group('default constructor', () {
      test('should create provider with default storage when none provided',
          () {
        final defaultProvider = SecureTokenProvider();

        expect(defaultProvider, isA<SecureTokenProvider>());
        expect(defaultProvider.accessTokenKey, 'apix_access_token');
        expect(defaultProvider.refreshTokenKey, 'apix_refresh_token');
      });
    });
  });
}
