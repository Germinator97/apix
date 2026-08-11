import 'dart:async';
import 'dart:convert';

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [body] and returns every error that escaped to the zone rather than to
/// a caller.
///
/// This is the only way to observe the defect: the request itself fails exactly
/// as it should, the caller catches exactly what it expects, and *in addition*
/// an error surfaces with no one to receive it. Nothing in the call site can
/// see that second error — only the zone can.
Future<List<Object>> escapedErrors(Future<void> Function() body) async {
  final escaped = <Object>[];
  final done = Completer<void>();

  runZonedGuarded(
    () async {
      try {
        await body();
      } finally {
        // Give any orphaned completion a turn to surface before we look.
        await Future<void>.delayed(Duration.zero);
        if (!done.isCompleted) done.complete();
      }
    },
    (error, stack) => escaped.add(error),
  );

  await done.future;
  await Future<void>.delayed(Duration.zero);
  return escaped;
}

void main() {
  group('RequestDeduplicator — a rejected future nobody listens to', () {
    // The asymmetry that hid this: completing with a *value* and no listener is
    // harmless, rejecting with no listener is not. So only the failure path
    // shows it, and on GETs failures are rare — until a CancelToken makes
    // cancellation routine.
    test('a lone failing request leaks nothing to the zone', () async {
      final deduplicator = RequestDeduplicator();
      final options = RequestOptions(path: '/search', method: 'GET');

      final escaped = await escapedErrors(() async {
        await expectLater(
          deduplicator.deduplicate(
            options,
            () async => throw DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          ),
          throwsA(isA<DioException>()),
        );
      });

      expect(
        escaped,
        isEmpty,
        reason: 'the caller already received this failure; a second, '
            'unhandled copy reaching the zone is what Sentry reports',
      );
    });

    test('a lone succeeding request leaks nothing either', () async {
      final deduplicator = RequestDeduplicator();
      final options = RequestOptions(path: '/search', method: 'GET');

      final escaped = await escapedErrors(() async {
        await deduplicator.deduplicate(
          options,
          () async => Response<dynamic>(requestOptions: options, data: 'ok'),
        );
      });

      expect(escaped, isEmpty);
    });

    // The other half. Silencing the orphan must not silence the waiter: a
    // request that failed while a duplicate was queued behind it still owes
    // that duplicate the error.
    test('a waiting duplicate still receives the failure', () async {
      final deduplicator = RequestDeduplicator();
      final options = RequestOptions(path: '/search', method: 'GET');
      final gate = Completer<void>();

      final escaped = await escapedErrors(() async {
        final first = deduplicator.deduplicate(options, () async {
          await gate.future;
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          );
        });
        // Let the first registration land before the duplicate arrives.
        await Future<void>.delayed(Duration.zero);
        final second = deduplicator.deduplicate(
          options,
          () async => throw StateError('the duplicate must not execute'),
        );

        gate.complete();

        await expectLater(first, throwsA(isA<DioException>()));
        await expectLater(
          second,
          throwsA(isA<DioException>()),
          reason: 'the waiter was merged into the failing request, so it must '
              'receive that failure — not hang, not succeed',
        );
      });

      expect(escaped, isEmpty);
    });

    test('a waiting duplicate still receives the response', () async {
      final deduplicator = RequestDeduplicator();
      final options = RequestOptions(path: '/search', method: 'GET');
      final gate = Completer<void>();

      final escaped = await escapedErrors(() async {
        final first = deduplicator.deduplicate(options, () async {
          await gate.future;
          return Response<dynamic>(requestOptions: options, data: 'shared');
        });
        await Future<void>.delayed(Duration.zero);
        final second = deduplicator.deduplicate(
          options,
          () async => throw StateError('the duplicate must not execute'),
        );

        gate.complete();

        expect((await first).data, equals('shared'));
        expect((await second).data, equals('shared'));
      });

      expect(escaped, isEmpty);
    });
  });

  group('through a real client', () {
    // a consumer hit this with a CancelToken on a search field: every keystroke
    // cancelled the in-flight GET, turning a rare failure path into one taken
    // on every character typed.
    test('a cancelled request leaks nothing — standalone deduplication',
        () async {
      final escaped = await escapedErrors(() async {
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.test',
          deduplicationConfig: const DeduplicationConfig(),
          httpClientAdapter: _SlowAdapter(),
        );
        final token = CancelToken();

        final inFlight = client.get<dynamic>('/search', cancelToken: token);
        // Long enough for the request to actually reach the adapter: cancelling
        // before it is in flight exercises a different path entirely, and the
        // test would pass while proving nothing.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        token.cancel('replaced by the next keystroke');

        await expectLater(inFlight, throwsA(isA<ApiException>()));
      });

      expect(
        escaped,
        isEmpty,
        reason: 'this is the configuration 4.0.0 made easy to enable — the '
            'defect would have travelled with it',
      );
    });

    test('a cancelled request leaks nothing — deduplication via the cache',
        () async {
      final escaped = await escapedErrors(() async {
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.test',
          cacheConfig: CacheConfig(strategy: CacheStrategy.networkFirst),
          httpClientAdapter: _SlowAdapter(),
        );
        final token = CancelToken();

        final inFlight = client.get<dynamic>('/search', cancelToken: token);
        // Long enough for the request to actually reach the adapter: cancelling
        // before it is in flight exercises a different path entirely, and the
        // test would pass while proving nothing.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        token.cancel('replaced by the next keystroke');

        await expectLater(inFlight, throwsA(isA<ApiException>()));
      });

      expect(escaped, isEmpty, reason: 'the 3.0.0 path a consumer reported on');
    });
  });
}

/// Answers slowly enough that a cancellation lands while the request is still
/// in flight — the condition a consumer had to create by throttling their API
/// to 8 s before the defect would show at all.
class _SlowAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'value': 'ok'})),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
