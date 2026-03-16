import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

class MockTokenProvider implements TokenProvider {
  String? accessToken;
  String? refreshToken;

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }
}

class TestHandler extends RequestInterceptorHandler {
  bool nextCalled = false;
  RequestOptions? lastOptions;

  @override
  void next(RequestOptions requestOptions) {
    nextCalled = true;
    lastOptions = requestOptions;
  }
}

void main() {
  group('AuthInterceptor', () {
    late MockTokenProvider tokenProvider;
    late AuthConfig authConfig;
    late AuthInterceptor interceptor;

    setUp(() {
      tokenProvider = MockTokenProvider();
      authConfig = AuthConfig(tokenProvider: tokenProvider);
      interceptor = AuthInterceptor(authConfig);
    });

    test('adds Authorization header when token is available', () async {
      tokenProvider.accessToken = 'test_token_123';
      final options = RequestOptions(path: '/api/users');
      final handler = TestHandler();

      interceptor.onRequest(options, handler);
      await Future<void>.delayed(Duration.zero);

      expect(handler.nextCalled, isTrue);
      expect(
        handler.lastOptions?.headers['Authorization'],
        equals('Bearer test_token_123'),
      );
    });

    test('does not add header when token is null', () async {
      tokenProvider.accessToken = null;
      final options = RequestOptions(path: '/api/users');
      final handler = TestHandler();

      interceptor.onRequest(options, handler);
      await Future<void>.delayed(Duration.zero);

      expect(handler.nextCalled, isTrue);
      expect(handler.lastOptions?.headers['Authorization'], isNull);
    });

    test('uses custom header name from config', () async {
      tokenProvider.accessToken = 'test_token';
      authConfig = AuthConfig(
        tokenProvider: tokenProvider,
        headerName: 'X-Auth-Token',
      );
      interceptor = AuthInterceptor(authConfig);

      final options = RequestOptions(path: '/api/users');
      final handler = TestHandler();

      interceptor.onRequest(options, handler);
      await Future<void>.delayed(Duration.zero);

      expect(handler.lastOptions?.headers['X-Auth-Token'], isNotNull);
      expect(handler.lastOptions?.headers['Authorization'], isNull);
    });

    test('uses custom header prefix from config', () async {
      tokenProvider.accessToken = 'test_token';
      authConfig = AuthConfig(
        tokenProvider: tokenProvider,
        headerPrefix: 'Token',
      );
      interceptor = AuthInterceptor(authConfig);

      final options = RequestOptions(path: '/api/users');
      final handler = TestHandler();

      interceptor.onRequest(options, handler);
      await Future<void>.delayed(Duration.zero);

      expect(
        handler.lastOptions?.headers['Authorization'],
        equals('Token test_token'),
      );
    });

    test('uses no prefix when headerPrefix is empty', () async {
      tokenProvider.accessToken = 'raw_token_value';
      authConfig = AuthConfig(
        tokenProvider: tokenProvider,
        headerPrefix: '',
      );
      interceptor = AuthInterceptor(authConfig);

      final options = RequestOptions(path: '/api/users');
      final handler = TestHandler();

      interceptor.onRequest(options, handler);
      await Future<void>.delayed(Duration.zero);

      expect(
        handler.lastOptions?.headers['Authorization'],
        equals('raw_token_value'),
      );
    });

    test('preserves existing headers', () async {
      tokenProvider.accessToken = 'test_token';
      final options = RequestOptions(
        path: '/api/users',
        headers: {'X-Custom-Header': 'custom_value'},
      );
      final handler = TestHandler();

      interceptor.onRequest(options, handler);
      await Future<void>.delayed(Duration.zero);

      expect(
        handler.lastOptions?.headers['X-Custom-Header'],
        equals('custom_value'),
      );
      expect(handler.lastOptions?.headers['Authorization'], isNotNull);
    });

    test('always calls handler.next', () async {
      final options = RequestOptions(path: '/api/users');
      final handler = TestHandler();

      interceptor.onRequest(options, handler);
      await Future<void>.delayed(Duration.zero);

      expect(handler.nextCalled, isTrue);
    });
  });
}
