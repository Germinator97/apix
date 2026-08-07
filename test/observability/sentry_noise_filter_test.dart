import 'dart:async' as async;
import 'dart:io' as io;

import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Guards `SentrySetup.isNetworkNoiseError`, which decides what never reaches
/// Sentry. It had no test at all, and was silently discarding every server
/// error ApiX reported.
///
/// The mechanism: `SentryException.type` is `throwable.runtimeType.toString()`
/// — a **bare** class name, never package-qualified (see
/// `SentryExceptionFactory`). ApiX names three of its exceptions exactly like
/// `dart:io` / `dart:async` ones — `HttpException`, `ClientException`,
/// `TimeoutException` — so any filter keyed on the name alone cannot tell a
/// 500 from the server apart from a socket-level `HttpException`.
void main() {
  /// Builds the event the way the Sentry SDK does: bare runtime type name,
  /// and the original object kept in `throwable`.
  SentryEvent eventFor(Object error) => SentryEvent(
        exceptions: [
          SentryException(
            type: error.runtimeType.toString(),
            value: error.toString(),
            throwable: error,
          ),
        ],
      );

  /// Same event, but with the throwable dropped — the degraded case (an event
  /// rebuilt from serialized data), where only the name is available.
  SentryEvent eventWithoutThrowable(String type, {String value = ''}) =>
      SentryEvent(
        exceptions: [SentryException(type: type, value: value)],
      );

  group('ApiX exceptions are classified by hierarchy, not by name', () {
    test('server and client errors are REPORTED, never filtered', () {
      final reportable = <ApiException>[
        const ServerException(message: 'boom', statusCode: 500),
        const ClientException(message: 'nope', statusCode: 400),
        const HttpException(message: 'weird', statusCode: 302),
        const NotFoundException(message: 'missing'),
        const UnauthorizedException(message: 'expired'),
        const ForbiddenException(message: 'denied'),
        const ParsingException(message: 'bad json'),
      ];

      for (final e in reportable) {
        expect(
          SentrySetup.isNetworkNoiseError(eventFor(e)),
          isFalse,
          reason:
              '${e.runtimeType} is a real error — dropping it hides genuine '
              'failures from Sentry',
        );
      }
    });

    test('ApiX transport failures ARE filtered as noise', () {
      final noise = <ApiException>[
        const TimeoutException(message: 'timed out'),
        const ConnectionException(message: 'offline'),
      ];

      for (final e in noise) {
        expect(
          SentrySetup.isNetworkNoiseError(eventFor(e)),
          isTrue,
          reason: '${e.runtimeType} is transport noise',
        );
      }
    });

    test(
      'an ApiX HttpException is not confused with the dart:io one',
      () {
        // Both stringify to the same bare type name. Only the throwable
        // distinguishes them — this is the exact confusion that silently
        // dropped every 5xx.
        const apixError = HttpException(message: 'boom', statusCode: 500);
        const dartError = io.HttpException('Connection closed');

        expect(
          apixError.runtimeType.toString(),
          dartError.runtimeType.toString(),
          reason: 'the premise of this test: if the names ever stop colliding, '
              'the name-based fallback below is no longer ambiguous',
        );

        expect(SentrySetup.isNetworkNoiseError(eventFor(apixError)), isFalse);
      },
    );

    test('an ApiX TimeoutException and the dart:async one agree', () {
      // Both are genuine transport noise, so here the collision is harmless.
      const apixTimeout = TimeoutException(message: 'timed out');
      final dartTimeout = async.TimeoutException('timed out');

      expect(SentrySetup.isNetworkNoiseError(eventFor(apixTimeout)), isTrue);
      expect(SentrySetup.isNetworkNoiseError(eventFor(dartTimeout)), isTrue);
    });
  });

  group('unambiguous transport types are still filtered', () {
    test('SocketException / HandshakeException / TlsException', () {
      for (final type in [
        'SocketException',
        'HandshakeException',
        'TlsException',
        'dart:io.SocketException',
      ]) {
        expect(
          SentrySetup.isNetworkNoiseError(eventWithoutThrowable(type)),
          isTrue,
          reason: '$type has no ApiX namesake — safe to match by name',
        );
      }
    });

    test('network error messages are filtered', () {
      expect(
        SentrySetup.isNetworkNoiseError(
          eventWithoutThrowable('Whatever', value: 'Connection refused'),
        ),
        isTrue,
      );
    });
  });

  group('name matching still applies to everything that is not ApiX', () {
    test('a bare ambiguous name is filtered when no throwable disambiguates',
        () {
      // Deliberately unchanged from the pre-fix behaviour. In practice the
      // Sentry SDK always attaches the throwable, so ApiX exceptions never
      // reach this branch; narrowing it would stop filtering genuine
      // `dart:` transport errors for no gain.
      for (final type in ['HttpException', 'ClientException']) {
        expect(
          SentrySetup.isNetworkNoiseError(eventWithoutThrowable(type)),
          isTrue,
          reason: '$type without a throwable stays best-effort name matching',
        );
      }
    });

    test('an explicitly dart:-qualified name is filtered', () {
      expect(
        SentrySetup.isNetworkNoiseError(
          eventWithoutThrowable('dart:io.HttpException'),
        ),
        isTrue,
      );
    });

    test('an unrelated type is not filtered', () {
      expect(
        SentrySetup.isNetworkNoiseError(eventWithoutThrowable('StateError')),
        isFalse,
      );
    });
  });
}
