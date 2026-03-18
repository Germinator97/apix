import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Auth Integration Tests', () {
    group('AuthConfig', () {
      test('creates with required tokenProvider', () {
        final config = AuthConfig(
          tokenProvider: _TestTokenProvider(),
        );

        expect(config.tokenProvider, isNotNull);
        expect(config.refreshEndpoint, isNull);
      });

      test('creates with refresh endpoint', () {
        final config = AuthConfig(
          tokenProvider: _TestTokenProvider(),
          refreshEndpoint: '/auth/refresh',
        );

        expect(config.refreshEndpoint, '/auth/refresh');
      });

      test('creates with onTokenRefreshed callback', () {
        final config = AuthConfig(
          tokenProvider: _TestTokenProvider(),
          refreshEndpoint: '/auth/refresh',
          onTokenRefreshed: (_) async {},
        );

        expect(config.onTokenRefreshed, isNotNull);
      });
    });

    group('RetryConfig', () {
      test('default values are sensible', () {
        const config = RetryConfig();

        expect(config.maxAttempts, 3);
        expect(config.baseDelayMs, 1000);
        expect(config.multiplier, 2.0);
        expect(config.retryStatusCodes, contains(500));
      });

      test('custom values are respected', () {
        const config = RetryConfig(
          maxAttempts: 5,
          baseDelayMs: 500,
          multiplier: 1.5,
          retryStatusCodes: [502, 503, 504],
        );

        expect(config.maxAttempts, 5);
        expect(config.baseDelayMs, 500);
        expect(config.multiplier, 1.5);
        expect(config.retryStatusCodes, [502, 503, 504]);
      });

      test('shouldRetry checks status codes', () {
        const config = RetryConfig(retryStatusCodes: [500, 502]);

        expect(config.shouldRetry(500), true);
        expect(config.shouldRetry(502), true);
        expect(config.shouldRetry(400), false);
        expect(config.shouldRetry(404), false);
      });
    });

    group('SecureTokenProvider', () {
      test('implements TokenProvider interface', () {
        final provider = SecureTokenProvider();
        expect(provider, isA<TokenProvider>());
      });

      test('has default storage keys', () {
        final provider = SecureTokenProvider();
        expect(provider.accessTokenKey, 'apix_access_token');
        expect(provider.refreshTokenKey, 'apix_refresh_token');
      });

      test('accepts custom storage keys', () {
        final provider = SecureTokenProvider(
          accessTokenKey: 'custom_access',
          refreshTokenKey: 'custom_refresh',
        );

        expect(provider.accessTokenKey, 'custom_access');
        expect(provider.refreshTokenKey, 'custom_refresh');
      });
    });
  });
}

class _TestTokenProvider implements TokenProvider {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<String?> getAccessToken() async => _accessToken;

  @override
  Future<String?> getRefreshToken() async => _refreshToken;

  @override
  Future<void> saveTokens(String accessToken, String? refreshToken) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }
}
