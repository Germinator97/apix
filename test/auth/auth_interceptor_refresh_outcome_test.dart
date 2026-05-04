import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTokenProvider implements TokenProvider {
  String? access;
  String? refresh;

  @override
  Future<String?> getAccessToken() async => access;

  @override
  Future<String?> getRefreshToken() async => refresh;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    access = null;
    refresh = null;
  }
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  /// Each entry handles one fetch in order. Functions may throw a
  /// [DioException] to simulate network failures.
  final List<ResponseBody Function(RequestOptions options)> script;
  int _i = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_i >= script.length) {
      throw StateError('No scripted response left for ${options.path}');
    }
    final fn = script[_i++];
    return fn(options);
  }
}

ResponseBody _json(String body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

void main() {
  group('AuthInterceptor refresh outcome distinguishes network vs auth', () {
    test(
      'refresh request fails with connection error → original request rejected with ConnectionException, onAuthFailure NOT called',
      () async {
        final tokenProvider = _MemoryTokenProvider()
          ..access = 'expired-access'
          ..refresh = 'valid-refresh';

        var onAuthFailureCalled = false;
        Object? capturedError;

        final adapter = _ScriptedAdapter([
          // 1) original request → 401
          (req) => _json('{"message":"unauthorized"}', statusCode: 401),
          // 2) refresh request → connection error
          (req) => throw DioException.connectionError(
                requestOptions: req,
                reason: 'No internet',
              ),
        ]);

        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          authConfig: AuthConfig(
            tokenProvider: tokenProvider,
            refreshEndpoint: '/auth/refresh',
            onTokenRefreshed: (response) async {},
            onAuthFailure: (provider, error) async {
              onAuthFailureCalled = true;
              capturedError = error;
            },
          ),
          httpClientAdapter: adapter,
        );

        try {
          await client.get<dynamic>('/me');
          fail('expected ConnectionException');
        } on ConnectionException {
          // expected
        } on ApiException catch (e) {
          fail('expected ConnectionException, got ${e.runtimeType}: $e');
        }

        expect(
          onAuthFailureCalled,
          isFalse,
          reason: 'network blip must not log the user out',
        );
        expect(capturedError, isNull);
      },
    );

    test(
      'refresh request fails with timeout → TimeoutException, onAuthFailure NOT called',
      () async {
        final tokenProvider = _MemoryTokenProvider()
          ..access = 'expired'
          ..refresh = 'r';

        var onAuthFailureCalled = false;

        final adapter = _ScriptedAdapter([
          (req) => _json('{}', statusCode: 401),
          (req) => throw DioException.connectionTimeout(
                requestOptions: req,
                timeout: const Duration(seconds: 5),
              ),
        ]);

        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          authConfig: AuthConfig(
            tokenProvider: tokenProvider,
            refreshEndpoint: '/auth/refresh',
            onTokenRefreshed: (response) async {},
            onAuthFailure: (provider, error) async {
              onAuthFailureCalled = true;
            },
          ),
          httpClientAdapter: adapter,
        );

        await expectLater(
          () => client.get<dynamic>('/me'),
          throwsA(isA<TimeoutException>()),
        );
        expect(onAuthFailureCalled, isFalse);
      },
    );

    test(
      'refresh request fails with 401 → AuthException, onAuthFailure called (regression)',
      () async {
        final tokenProvider = _MemoryTokenProvider()
          ..access = 'expired'
          ..refresh = 'r';

        var onAuthFailureCalled = false;

        final adapter = _ScriptedAdapter([
          (req) => _json('{}', statusCode: 401),
          // refresh endpoint also returns 401
          (req) => _json('{"error":"refresh expired"}', statusCode: 401),
        ]);

        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          authConfig: AuthConfig(
            tokenProvider: tokenProvider,
            refreshEndpoint: '/auth/refresh',
            onTokenRefreshed: (response) async {},
            onAuthFailure: (provider, error) async {
              onAuthFailureCalled = true;
            },
          ),
          httpClientAdapter: adapter,
        );

        await expectLater(
          () => client.get<dynamic>('/me'),
          throwsA(isA<AuthException>()),
        );
        expect(onAuthFailureCalled, isTrue);
      },
    );

    test(
      'getRefreshToken throws → original request rejected with TokenProviderException',
      () async {
        final adapter = _ScriptedAdapter([
          (req) => _json('{}', statusCode: 401),
        ]);

        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          authConfig: AuthConfig(
            tokenProvider: _ThrowingRefreshTokenProvider(),
            refreshEndpoint: '/auth/refresh',
            onTokenRefreshed: (response) async {},
          ),
          httpClientAdapter: adapter,
        );

        try {
          await client.get<dynamic>('/me');
          fail('expected TokenProviderException');
        } on TokenProviderException catch (e) {
          expect(e.operation, equals(TokenProviderOperation.read));
          expect(e.originalError, isA<StateError>());
        }
      },
    );

    test(
      'AuthException preserves originalError when refresh aborts on a typed cause',
      () async {
        final tokenProvider = _MemoryTokenProvider()
          ..access = 'expired'
          ..refresh = 'r';

        // Force the legacy onRefresh to throw a non-network, non-token
        // exception so the outcome is auth-class with a typed cause.
        final adapter = _ScriptedAdapter([
          (req) => _json('{}', statusCode: 401),
        ]);

        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          authConfig: AuthConfig(
            tokenProvider: tokenProvider,
            onRefresh: (provider) async {
              throw const FormatException('garbled token blob');
            },
          ),
          httpClientAdapter: adapter,
        );

        try {
          await client.get<dynamic>('/me');
          fail('expected AuthException');
        } on AuthException catch (e) {
          expect(e.originalError, isA<FormatException>());
        }
      },
    );
  });
}

class _ThrowingRefreshTokenProvider implements TokenProvider {
  @override
  Future<String?> getAccessToken() async => 'expired';

  @override
  Future<String?> getRefreshToken() async {
    throw StateError('keychain corrupted');
  }

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {}

  @override
  Future<void> clearTokens() async {}
}
