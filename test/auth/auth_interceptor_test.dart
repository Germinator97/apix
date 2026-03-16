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
    late Dio dio;

    setUp(() {
      tokenProvider = MockTokenProvider();
      authConfig = AuthConfig(tokenProvider: tokenProvider);
      dio = Dio();
      interceptor = AuthInterceptor(authConfig, dio);
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
      interceptor = AuthInterceptor(authConfig, dio);

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
      interceptor = AuthInterceptor(authConfig, dio);

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
      interceptor = AuthInterceptor(authConfig, dio);

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

  group('AuthInterceptor refresh detection', () {
    late MockTokenProvider tokenProvider;
    late Dio dio;

    setUp(() {
      tokenProvider = MockTokenProvider();
      dio = Dio();
    });

    test('shouldRefresh returns true for configured status codes', () {
      final config = AuthConfig(
        tokenProvider: tokenProvider,
        refreshStatusCodes: [401, 403],
      );

      expect(config.shouldRefresh(401), isTrue);
      expect(config.shouldRefresh(403), isTrue);
      expect(config.shouldRefresh(404), isFalse);
      expect(config.shouldRefresh(500), isFalse);
    });

    test('shouldRefresh defaults to [401]', () {
      final config = AuthConfig(tokenProvider: tokenProvider);

      expect(config.shouldRefresh(401), isTrue);
      expect(config.shouldRefresh(403), isFalse);
    });

    test('onRefresh callback is called on refresh status code', () async {
      var refreshCalled = false;

      final config = AuthConfig(
        tokenProvider: tokenProvider,
        onRefresh: (provider) async {
          refreshCalled = true;
          await provider.saveTokens('new_access', 'new_refresh');
          return true;
        },
      );

      final interceptor = AuthInterceptor(config, dio);
      final handler = TestErrorHandler();

      final error = DioException(
        requestOptions: RequestOptions(path: '/api/users'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/users'),
          statusCode: 401,
        ),
      );

      interceptor.onError(error, handler);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(refreshCalled, isTrue);
    });

    test('does not call onRefresh for non-refresh status codes', () async {
      var refreshCalled = false;

      final config = AuthConfig(
        tokenProvider: tokenProvider,
        onRefresh: (provider) async {
          refreshCalled = true;
          return true;
        },
      );

      final interceptor = AuthInterceptor(config, dio);
      final handler = TestErrorHandler();

      final error = DioException(
        requestOptions: RequestOptions(path: '/api/users'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/users'),
          statusCode: 404,
        ),
      );

      interceptor.onError(error, handler);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(refreshCalled, isFalse);
      expect(handler.nextCalled, isTrue);
    });

    test('does not call refresh when onRefresh is null', () async {
      final config = AuthConfig(tokenProvider: tokenProvider);
      final interceptor = AuthInterceptor(config, dio);
      final handler = TestErrorHandler();

      final error = DioException(
        requestOptions: RequestOptions(path: '/api/users'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/users'),
          statusCode: 401,
        ),
      );

      interceptor.onError(error, handler);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.nextCalled, isTrue);
    });
  });
}

class TestErrorHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;
  bool resolveCalled = false;
  DioException? lastError;
  Response<dynamic>? lastResponse;

  @override
  void next(DioException err) {
    nextCalled = true;
    lastError = err;
  }

  @override
  void resolve(Response<dynamic> response) {
    resolveCalled = true;
    lastResponse = response;
  }
}
