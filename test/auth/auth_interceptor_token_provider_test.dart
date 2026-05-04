import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingTokenProvider implements TokenProvider {
  _ThrowingTokenProvider({this.onRead});

  final Object Function()? onRead;

  @override
  Future<String?> getAccessToken() async {
    if (onRead != null) throw onRead!();
    return null;
  }

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {}

  @override
  Future<void> clearTokens() async {}
}

class _CapturingHandler extends RequestInterceptorHandler {
  bool nextCalled = false;
  bool rejectCalled = false;
  DioException? rejection;

  @override
  void next(RequestOptions requestOptions) {
    nextCalled = true;
  }

  @override
  void reject(DioException error,
      [bool callFollowingErrorInterceptor = false]) {
    rejectCalled = true;
    rejection = error;
  }
}

void main() {
  group('AuthInterceptor wraps TokenProvider failures', () {
    test(
      'getAccessToken that throws → request rejected with TokenProviderException',
      () async {
        final provider = _ThrowingTokenProvider(
          onRead: () => const FormatException('keychain corrupted'),
        );
        final config = AuthConfig(tokenProvider: provider);
        final interceptor = AuthInterceptor(config, Dio());

        final handler = _CapturingHandler();
        interceptor.onRequest(RequestOptions(path: '/me'), handler);
        await Future<void>.delayed(Duration.zero);

        expect(handler.rejectCalled, isTrue);
        expect(handler.nextCalled, isFalse);

        final inner = handler.rejection!.error;
        expect(inner, isA<TokenProviderException>());
        final tokenError = inner! as TokenProviderException;
        expect(tokenError.operation, equals(TokenProviderOperation.read));
        expect(tokenError.message, contains('keychain corrupted'));
        expect(tokenError.originalError, isA<FormatException>());
      },
    );

    test(
      'normal flow when getAccessToken returns null is unaffected (regression)',
      () async {
        final provider = _ThrowingTokenProvider();
        final config = AuthConfig(tokenProvider: provider);
        final interceptor = AuthInterceptor(config, Dio());

        final handler = _CapturingHandler();
        interceptor.onRequest(RequestOptions(path: '/me'), handler);
        await Future<void>.delayed(Duration.zero);

        expect(handler.nextCalled, isTrue);
        expect(handler.rejectCalled, isFalse);
      },
    );
  });
}
