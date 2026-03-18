import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apix/src/auth/auth_config.dart';
import 'package:apix/src/auth/token_provider.dart';

class MockTokenProvider extends Mock implements TokenProvider {}

class MockResponse extends Mock implements Response<dynamic> {}

void main() {
  late MockTokenProvider mockTokenProvider;

  setUp(() {
    mockTokenProvider = MockTokenProvider();
  });

  group('AuthConfig', () {
    group('constructor defaults', () {
      test('should have default headerName as Authorization', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.headerName, 'Authorization');
      });

      test('should have default headerPrefix as Bearer', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.headerPrefix, 'Bearer');
      });

      test('should have default refreshStatusCodes as [401]', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.refreshStatusCodes, [401]);
      });

      test('should have default refreshTokenBodyKey as refresh_token', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.refreshTokenBodyKey, 'refresh_token');
      });

      test('should have null onRefresh by default', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.onRefresh, isNull);
      });

      test('should have null refreshEndpoint by default', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.refreshEndpoint, isNull);
      });

      test('should have null refreshHeaders by default', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.refreshHeaders, isNull);
      });

      test('should have null onTokenRefreshed by default', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.onTokenRefreshed, isNull);
      });
    });

    group('formatHeaderValue', () {
      test('should format with prefix', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.formatHeaderValue('token123'), 'Bearer token123');
      });

      test('should format without prefix when empty', () {
        final config = AuthConfig(
          tokenProvider: mockTokenProvider,
          headerPrefix: '',
        );

        expect(config.formatHeaderValue('token123'), 'token123');
      });

      test('should format with custom prefix', () {
        final config = AuthConfig(
          tokenProvider: mockTokenProvider,
          headerPrefix: 'Token',
        );

        expect(config.formatHeaderValue('abc'), 'Token abc');
      });
    });

    group('shouldRefresh', () {
      test('should return true for 401 with default codes', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.shouldRefresh(401), isTrue);
      });

      test('should return false for 403 with default codes', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.shouldRefresh(403), isFalse);
      });

      test('should return true for custom refresh codes', () {
        final config = AuthConfig(
          tokenProvider: mockTokenProvider,
          refreshStatusCodes: [401, 403],
        );

        expect(config.shouldRefresh(401), isTrue);
        expect(config.shouldRefresh(403), isTrue);
      });
    });

    group('hasSimplifiedRefresh', () {
      test('should return false when refreshEndpoint is null', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        expect(config.hasSimplifiedRefresh, isFalse);
      });

      test('should return true when refreshEndpoint is set', () {
        final config = AuthConfig(
          tokenProvider: mockTokenProvider,
          refreshEndpoint: '/auth/refresh',
        );

        expect(config.hasSimplifiedRefresh, isTrue);
      });
    });

    group('simplified refresh configuration', () {
      test('should store refreshEndpoint', () {
        final config = AuthConfig(
          tokenProvider: mockTokenProvider,
          refreshEndpoint: '/api/v1/token/refresh',
        );

        expect(config.refreshEndpoint, '/api/v1/token/refresh');
      });

      test('should store refreshHeaders', () {
        final config = AuthConfig(
          tokenProvider: mockTokenProvider,
          refreshHeaders: {'X-Custom': 'value'},
        );

        expect(config.refreshHeaders, {'X-Custom': 'value'});
      });

      test('should store onTokenRefreshed callback', () async {
        var callbackCalled = false;
        final mockResponse = MockResponse();

        final config = AuthConfig(
          tokenProvider: mockTokenProvider,
          onTokenRefreshed: (response) async {
            callbackCalled = true;
          },
        );

        await config.onTokenRefreshed!(mockResponse);
        expect(callbackCalled, isTrue);
      });

      test('should store custom refreshTokenBodyKey', () {
        final config = AuthConfig(
          tokenProvider: mockTokenProvider,
          refreshTokenBodyKey: 'token',
        );

        expect(config.refreshTokenBodyKey, 'token');
      });
    });

    group('copyWith', () {
      test('should copy with new tokenProvider', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);
        final newProvider = MockTokenProvider();

        final copied = config.copyWith(tokenProvider: newProvider);

        expect(copied.tokenProvider, newProvider);
      });

      test('should copy with new refreshEndpoint', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        final copied = config.copyWith(refreshEndpoint: '/new/endpoint');

        expect(copied.refreshEndpoint, '/new/endpoint');
      });

      test('should copy with new refreshHeaders', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        final copied = config.copyWith(refreshHeaders: {'X-New': 'header'});

        expect(copied.refreshHeaders, {'X-New': 'header'});
      });

      test('should copy with new onTokenRefreshed', () async {
        final config = AuthConfig(tokenProvider: mockTokenProvider);
        var called = false;

        final copied = config.copyWith(
          onTokenRefreshed: (_) async => called = true,
        );

        await copied.onTokenRefreshed!(MockResponse());
        expect(called, isTrue);
      });

      test('should copy with new refreshTokenBodyKey', () {
        final config = AuthConfig(tokenProvider: mockTokenProvider);

        final copied = config.copyWith(refreshTokenBodyKey: 'new_key');

        expect(copied.refreshTokenBodyKey, 'new_key');
      });

      test('should preserve existing values when not overridden', () {
        final config = AuthConfig(
          tokenProvider: mockTokenProvider,
          refreshEndpoint: '/auth/refresh',
          refreshHeaders: {'X-Custom': 'value'},
          headerName: 'X-Auth',
        );

        final copied = config.copyWith(headerPrefix: 'Token');

        expect(copied.refreshEndpoint, '/auth/refresh');
        expect(copied.refreshHeaders, {'X-Custom': 'value'});
        expect(copied.headerName, 'X-Auth');
        expect(copied.headerPrefix, 'Token');
      });
    });

    group('backward compatibility', () {
      test('should work with only tokenProvider and onRefresh (legacy)',
          () async {
        var refreshCalled = false;

        final config = AuthConfig(
          tokenProvider: mockTokenProvider,
          onRefresh: (provider) async {
            refreshCalled = true;
            return true;
          },
        );

        final result = await config.onRefresh!(mockTokenProvider);

        expect(refreshCalled, isTrue);
        expect(result, isTrue);
        expect(config.refreshEndpoint, isNull);
      });
    });
  });
}
