import 'dart:convert';
import 'dart:math';

import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [Random] that returns a scripted sequence, so a jittered delay can be
/// asserted exactly instead of within a tolerance.
class _ScriptedRandom implements Random {
  _ScriptedRandom(this.values);

  final List<double> values;
  int _i = 0;

  @override
  double nextDouble() => values[_i++ % values.length];

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  int nextInt(int max) => throw UnimplementedError();
}

void main() {
  group('RetryConfig.jitter', () {
    // The rule itself, not a restatement of the formula: asserting
    // `delay == base * pow(...) * factor` would recompute the implementation
    // and stay green no matter what the default became.
    test('is on by default', () {
      expect(
        const RetryConfig().jitter,
        greaterThan(0.0),
        reason: 'a deterministic backoff makes every client retry in lockstep '
            'after an outage; the default must protect consumers who never '
            'read the changelog',
      );
    });

    test('spreads a delay across ±jitter of the deterministic value', () {
      const config = RetryConfig(baseDelayMs: 1000, jitter: 0.2);

      // nextDouble() == 0.0 -> factor 1 - 0.2 ; == 1.0 -> factor 1 + 0.2
      expect(
        config.getDelay(0, random: _ScriptedRandom([0.0])).inMilliseconds,
        equals(800),
      );
      expect(
        config.getDelay(0, random: _ScriptedRandom([1.0])).inMilliseconds,
        equals(1200),
      );
      expect(
        config.getDelay(0, random: _ScriptedRandom([0.5])).inMilliseconds,
        equals(1000),
      );
    });

    test('jitter: 0 restores the exact previous behaviour', () {
      const config = RetryConfig(baseDelayMs: 1000, multiplier: 2, jitter: 0);

      // The pre-4.0.0 sequence, asserted as literals rather than recomputed.
      expect(config.getDelay(0).inMilliseconds, equals(1000));
      expect(config.getDelay(1).inMilliseconds, equals(2000));
      expect(config.getDelay(2).inMilliseconds, equals(4000));
    });

    test('two draws of the same attempt differ — the point of the feature', () {
      const config = RetryConfig(baseDelayMs: 1000, jitter: 0.2);
      final random = Random(20260810);

      final draws = List.generate(
        20,
        (_) => config.getDelay(3, random: random).inMilliseconds,
      ).toSet();

      expect(
        draws.length,
        greaterThan(1),
        reason: 'identical delays across draws would mean jitter never applied',
      );
    });

    test('keeps growing with the attempt number', () {
      const config = RetryConfig(baseDelayMs: 1000, multiplier: 2, jitter: 0.2);
      final random = Random(1);

      // ±20 % cannot make attempt N overtake attempt N+1 (1.2 < 2 * 0.8), so
      // ordering is a property of the design, not of the seed.
      final first = config.getDelay(0, random: random).inMilliseconds;
      final third = config.getDelay(2, random: random).inMilliseconds;

      expect(third, greaterThan(first));
    });

    test('never exceeds maxDelayMs, jitter included', () {
      const config = RetryConfig(
        baseDelayMs: 1000,
        multiplier: 2,
        maxDelayMs: 5000,
        jitter: 0.5,
      );

      for (var attempt = 0; attempt < 10; attempt++) {
        expect(
          config
              .getDelay(attempt, random: _ScriptedRandom([1.0]))
              .inMilliseconds,
          lessThanOrEqualTo(5000),
          reason: 'attempt $attempt escaped the cap once jittered upwards',
        );
      }
    });

    test('never produces a negative delay', () {
      const config = RetryConfig(baseDelayMs: 1000, jitter: 1.0);

      expect(
        config.getDelay(0, random: _ScriptedRandom([0.0])).inMilliseconds,
        greaterThanOrEqualTo(0),
      );
    });

    test('rejects a jitter outside [0, 1]', () {
      expect(() => RetryConfig(jitter: 1.5), throwsA(isA<AssertionError>()));
      expect(() => RetryConfig(jitter: -0.1), throwsA(isA<AssertionError>()));
    });

    test('survives copyWith and equality', () {
      const base = RetryConfig();
      final changed = base.copyWith(jitter: 0.5);

      expect(changed.jitter, equals(0.5));
      expect(changed, isNot(equals(base)));
      expect(base.copyWith(), equals(base));
    });
  });

  group('RetryInterceptor.onRetry', () {
    test('reports every retry, with its attempt number and cause', () async {
      final seen = <RetryAttempt>[];
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        retryConfig: const RetryConfig(maxAttempts: 2, baseDelayMs: 1),
        onRetry: seen.add,
        httpClientAdapter: _AlwaysFailsAdapter(),
      );

      try {
        await client.get<dynamic>('/flaky');
      } on ApiException {
        // The point is what onRetry saw on the way, not the final failure.
      }

      expect(seen, hasLength(2), reason: 'maxAttempts: 2 means two retries');
      expect(seen.map((a) => a.attempt), equals([0, 1]));
      expect(seen.every((a) => a.statusCode == 503), isTrue);
    });

    // The silent half: a callback is not supposed to be able to break the
    // request path it only observes.
    test('a throwing callback does not cancel the retry', () async {
      var calls = 0;
      final adapter = _AlwaysFailsAdapter();
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        retryConfig: const RetryConfig(maxAttempts: 2, baseDelayMs: 1),
        onRetry: (_) {
          calls++;
          throw StateError('breadcrumb backend is down');
        },
        httpClientAdapter: adapter,
      );

      try {
        await client.get<dynamic>('/flaky');
      } on ApiException {
        // The point is what onRetry saw on the way, not the final failure.
      }

      expect(calls, equals(2));
      expect(
        adapter.hits,
        equals(3),
        reason: 'the initial request plus both retries must still be sent',
      );
    });

    test('stays silent when nothing is retried', () async {
      final seen = <RetryAttempt>[];
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        retryConfig: const RetryConfig(maxAttempts: 2, baseDelayMs: 1),
        onRetry: seen.add,
        httpClientAdapter: _SucceedsAdapter(),
      );

      await client.get<dynamic>('/ok');

      expect(seen, isEmpty);
    });
  });
}

/// Always answers 503, a status the default RetryConfig retries.
class _AlwaysFailsAdapter implements HttpClientAdapter {
  int hits = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    hits++;
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'message': 'unavailable'})),
      503,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SucceedsAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'ok': true})),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
