import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

/// Mock implementation of TokenProvider for testing.
class MockTokenProvider implements TokenProvider {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<String?> getAccessToken() async => _accessToken;

  @override
  Future<String?> getRefreshToken() async => _refreshToken;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }
}

void main() {
  group('TokenProvider', () {
    late MockTokenProvider provider;

    setUp(() {
      provider = MockTokenProvider();
    });

    test('getAccessToken returns null initially', () async {
      expect(await provider.getAccessToken(), isNull);
    });

    test('getRefreshToken returns null initially', () async {
      expect(await provider.getRefreshToken(), isNull);
    });

    test('saveTokens stores both tokens', () async {
      await provider.saveTokens('access123', 'refresh456');

      expect(await provider.getAccessToken(), equals('access123'));
      expect(await provider.getRefreshToken(), equals('refresh456'));
    });

    test('clearTokens removes all tokens', () async {
      await provider.saveTokens('access123', 'refresh456');
      await provider.clearTokens();

      expect(await provider.getAccessToken(), isNull);
      expect(await provider.getRefreshToken(), isNull);
    });

    test('saveTokens overwrites existing tokens', () async {
      await provider.saveTokens('old_access', 'old_refresh');
      await provider.saveTokens('new_access', 'new_refresh');

      expect(await provider.getAccessToken(), equals('new_access'));
      expect(await provider.getRefreshToken(), equals('new_refresh'));
    });
  });

  group('AuthConfig', () {
    late MockTokenProvider provider;

    setUp(() {
      provider = MockTokenProvider();
    });

    test('creates with required tokenProvider', () {
      final config = AuthConfig(tokenProvider: provider);

      expect(config.tokenProvider, equals(provider));
      expect(config.headerName, equals('Authorization'));
      expect(config.headerPrefix, equals('Bearer'));
      expect(config.refreshStatusCodes, equals([401]));
    });

    test('creates with custom header name', () {
      final config = AuthConfig(
        tokenProvider: provider,
        headerName: 'X-Auth-Token',
      );

      expect(config.headerName, equals('X-Auth-Token'));
    });

    test('creates with custom header prefix', () {
      final config = AuthConfig(
        tokenProvider: provider,
        headerPrefix: 'Token',
      );

      expect(config.headerPrefix, equals('Token'));
    });

    test('creates with empty header prefix', () {
      final config = AuthConfig(
        tokenProvider: provider,
        headerPrefix: '',
      );

      expect(config.headerPrefix, isEmpty);
    });

    test('creates with custom refresh status codes', () {
      final config = AuthConfig(
        tokenProvider: provider,
        refreshStatusCodes: [401, 403],
      );

      expect(config.refreshStatusCodes, equals([401, 403]));
    });

    test('formatHeaderValue with prefix', () {
      final config = AuthConfig(tokenProvider: provider);

      expect(config.formatHeaderValue('token123'), equals('Bearer token123'));
    });

    test('formatHeaderValue without prefix', () {
      final config = AuthConfig(
        tokenProvider: provider,
        headerPrefix: '',
      );

      expect(config.formatHeaderValue('token123'), equals('token123'));
    });

    test('copyWith creates new config with updated values', () {
      final original = AuthConfig(tokenProvider: provider);
      final copied = original.copyWith(
        headerName: 'X-Token',
        refreshStatusCodes: [401, 403],
      );

      expect(copied.headerName, equals('X-Token'));
      expect(copied.refreshStatusCodes, equals([401, 403]));
      expect(copied.tokenProvider, equals(provider));
      expect(original.headerName, equals('Authorization'));
    });
  });
}
