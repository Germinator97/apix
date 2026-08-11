import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on the in-flight ledger of [MetricsInterceptor].
///
/// The defect this pins produces nothing: no exception, no wrong number in a
/// callback, just entries that are never removed. It only shows on the one
/// reading nobody takes — `inFlightCount` — and then heals itself five minutes
/// later, which is exactly long enough to look like it was never there.
void main() {
  ({ApiClient client, MetricsInterceptor metrics, List<RequestMetrics> emitted})
      clientWith(
    ScriptedAdapter adapter, {
    RetryConfig? retry,
    AuthConfig? auth,
  }) {
    final emitted = <RequestMetrics>[];
    final client = ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
      retryConfig: retry,
      authConfig: auth,
      metricsConfig: MetricsConfig(onMetrics: emitted.add),
    );
    return (
      client: client,
      metrics: client.dio.interceptors.whereType<MetricsInterceptor>().first,
      emitted: emitted,
    );
  }

  group('N5 — a replay does not strand the entry it replaces', () {
    test('two retries leave nothing in flight', () async {
      final adapter = ScriptedAdapter(
        (options, i) =>
            i < 2 ? jsonResponse({'e': 1}, 503) : jsonResponse({'ok': 1}, 200),
      );
      final wired = clientWith(
        adapter,
        retry: const RetryConfig(maxAttempts: 2, baseDelayMs: 1, jitter: 0),
      );

      await wired.client.get<dynamic>('/x');

      expect(adapter.callCount, 3, reason: 'the request really was replayed');
      expect(
        wired.metrics.inFlightCount,
        0,
        reason: 'each attempt used to create a fresh entry and overwrite the '
            'id pointing at the previous one, stranding it until the '
            'five-minute sweep',
      );
      expect(wired.emitted, hasLength(1),
          reason: 'one logical request stays one measurement');
    });

    test('the measurement covers the whole logical request', () async {
      final adapter = ScriptedAdapter(
        (options, i) =>
            i == 0 ? jsonResponse({'e': 1}, 503) : jsonResponse({'ok': 1}, 200),
      );
      final wired = clientWith(
        adapter,
        retry: const RetryConfig(maxAttempts: 2, baseDelayMs: 40, jitter: 0),
      );

      await wired.client.get<dynamic>('/x');

      expect(
        wired.emitted.single.durationMs,
        greaterThanOrEqualTo(40),
        reason: 'reusing the entry means the duration includes the backoff the '
            'caller actually waited through, as the tracing span already did',
      );
      expect(wired.emitted.single.success, isTrue);
      expect(wired.emitted.single.statusCode, 200);
    });

    test('an auth replay after a refresh leaves nothing in flight', () async {
      final adapter = ScriptedAdapter((options, i) {
        if (options.path.contains('refresh')) {
          return jsonResponse(
              {'access_token': 'new', 'refresh_token': 'r'}, 200);
        }
        return i == 0
            ? jsonResponse({'e': 1}, 401)
            : jsonResponse({'ok': 1}, 200);
      });
      final provider = StubTokenProvider();
      final wired = clientWith(
        adapter,
        auth: AuthConfig(
          tokenProvider: provider,
          refreshEndpoint: '/auth/refresh',
          onTokenRefreshed: (response) async {
            final body = bodyOf(response);
            await provider.saveTokens(
              body['access_token'] as String,
              body['refresh_token'] as String,
            );
          },
        ),
      );

      await wired.client.get<dynamic>('/me');

      expect(wired.metrics.inFlightCount, 0);
    });

    // The other half: a consumer re-executing their own RequestOptions is not
    // a replay, and must be measured twice. Collapsing those would be the fix
    // cutting too far — and is the defect ObservationMarker.beginAttempt
    // already exists to prevent for the other observers.
    test('a consumer re-running the same RequestOptions gets two measurements',
        () async {
      final adapter =
          ScriptedAdapter((options, i) => jsonResponse({'ok': 1}, 200));
      final wired = clientWith(adapter);

      final options = RequestOptions(
        path: '/x',
        method: 'GET',
        baseUrl: 'https://api.test',
      );
      await wired.client.dio.fetch<dynamic>(options);
      await wired.client.dio.fetch<dynamic>(options);

      expect(wired.emitted, hasLength(2),
          reason: 'two executions the caller asked for are two requests');
      expect(wired.metrics.inFlightCount, 0);
    });

    test('a failed request still completes its entry', () async {
      final adapter =
          ScriptedAdapter((options, i) => jsonResponse({'e': 1}, 503));
      final wired = clientWith(
        adapter,
        retry: const RetryConfig(maxAttempts: 1, baseDelayMs: 1, jitter: 0),
      );

      await expectLater(
        wired.client.get<dynamic>('/x'),
        throwsA(isA<ApiException>()),
      );

      expect(wired.metrics.inFlightCount, 0);
      expect(wired.emitted.single.success, isFalse);
    });
  });
}
