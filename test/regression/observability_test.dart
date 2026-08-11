import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on what the observers actually receive.
///
/// These are the hardest defects in the package to notice, because a missing
/// event looks exactly like a quiet minute. Two of them were invisible for a
/// worse reason: the dashboards were never empty, they just showed a different
/// request than the one that failed.
void main() {
  group('B5 — a broken session reaches every observer', () {
    /// Wires a client whose refresh endpoint always rejects, and collects what
    /// each observer saw.
    ({
      ApiClient client,
      List<Object> captured,
      List<LogEntry> logged,
      List<RequestMetrics> measured,
    }) brokenSession() {
      final adapter = ScriptedAdapter((options, i) {
        if (options.path.contains('refresh')) {
          return jsonResponse({'message': 'invalid refresh token'}, 400);
        }
        return jsonResponse({'message': 'expired'}, 401);
      });
      final captured = <Object>[];
      final logged = <LogEntry>[];
      final measured = <RequestMetrics>[];

      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        authConfig: AuthConfig(
          tokenProvider: StubTokenProvider(),
          refreshEndpoint: '/auth/refresh',
          onTokenRefreshed: (response) async {},
        ),
        loggerConfig: LoggerConfig(
          level: LogLevel.error,
          logHandler: logged.add,
        ),
        errorTrackingConfig: ErrorTrackingConfig(
          onError: (exception, {stackTrace, extra, tags}) async =>
              captured.add(exception),
          captureStatusCodes: const {400, 401, 500},
        ),
        metricsConfig: MetricsConfig(onMetrics: measured.add),
      );

      return (
        client: client,
        captured: captured,
        logged: logged,
        measured: measured
      );
    }

    test('the failure the caller receives is logged', () async {
      final wired = brokenSession();

      await expectLater(
        wired.client.get<dynamic>('/me'),
        throwsA(isA<UnauthorizedException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The refresh call is a request of its own and was always logged, so the
      // log was never empty — it just never mentioned /me.
      expect(
        wired.logged.where((entry) => entry.url?.contains('/me') ?? false),
        isNotEmpty,
        reason: 'the /me failure, not only the internal refresh call, must be '
            'logged',
      );
    });

    test('the failure the caller receives reaches the tracker', () async {
      final wired = brokenSession();

      await expectLater(
        wired.client.get<dynamic>('/me'),
        throwsA(isA<UnauthorizedException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(wired.captured.whereType<UnauthorizedException>(), isNotEmpty,
          reason: 'a broken session is the most consequential failure an '
              'authenticated app has; it cannot be the one nobody sees');
    });

    test('the in-flight metric does not leak', () async {
      final wired = brokenSession();

      await expectLater(
        wired.client.get<dynamic>('/me'),
        throwsA(isA<UnauthorizedException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final metrics =
          wired.client.dio.interceptors.whereType<MetricsInterceptor>().single;
      expect(metrics.inFlightCount, 0,
          reason: 'the entry used to dangle until the five-minute sweep');

      final forMe =
          wired.measured.where((m) => m.path.contains('/me')).toList();
      expect(forMe, hasLength(1));
      expect(forMe.single.success, isFalse);
      expect(forMe.single.statusCode, 401);
    });

    test('the exception type callers catch is unchanged', () async {
      final wired = brokenSession();

      // Routing through the rest of the chain means the error mapper now sees
      // it too. It returns an ApiException untouched, so this must still be an
      // AuthException — the 1.x contract for an opaque refresh failure.
      await expectLater(
        wired.client.get<dynamic>('/me'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('a refresh that fails on the network is not reported as auth failure',
        () async {
      final adapter = ScriptedAdapter((options, i) {
        if (options.path.contains('refresh')) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'offline',
          );
        }
        return jsonResponse({'message': 'expired'}, 401);
      });
      final captured = <Object>[];
      var loggedOut = false;

      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        authConfig: AuthConfig(
          tokenProvider: StubTokenProvider(),
          refreshEndpoint: '/auth/refresh',
          onTokenRefreshed: (response) async {},
          onAuthFailure: (provider, error) async => loggedOut = true,
        ),
        errorTrackingConfig: ErrorTrackingConfig(
          onError: (exception, {stackTrace, extra, tags}) async =>
              captured.add(exception),
        ),
      );

      // The other direction: routing failures to the observers must not turn a
      // connectivity blip into a logout.
      await expectLater(
        client.get<dynamic>('/me'),
        throwsA(isA<NetworkException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(loggedOut, isFalse,
          reason: 'a network failure during refresh must never log the user '
              'out');
      expect(captured.whereType<NetworkException>(), isNotEmpty);
    });
  });

  group('B5 — a cacheOnly miss is observed too', () {
    test('the failure is measured and the in-flight entry is released',
        () async {
      final adapter = ScriptedAdapter((options, i) => jsonResponse({}, 200));
      final measured = <RequestMetrics>[];

      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        cacheConfig: CacheConfig(strategy: CacheStrategy.cacheOnly),
        metricsConfig: MetricsConfig(onMetrics: measured.add),
      );

      await expectLater(
        client.get<dynamic>('/never-cached'),
        throwsA(isA<CacheException>()),
      );

      expect(adapter.callCount, 0,
          reason: 'cacheOnly must not hit the network');
      final metrics =
          client.dio.interceptors.whereType<MetricsInterceptor>().single;
      expect(metrics.inFlightCount, 0);
    });
  });
}
