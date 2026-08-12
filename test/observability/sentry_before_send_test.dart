import 'dart:async';

import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Guards the two functions that decide what Sentry never sees.
///
/// `beforeSend` and `beforeSendTransaction` are filters, and a filter is the
/// one kind of component whose bug is invisible by construction: it produces an
/// absence, and an absence reads as a quiet day. These two sit inside the
/// reporting channel itself, so a mistake here also removes the instrument that
/// would have denounced it.
///
/// `isNetworkNoiseError` had exactly that history — it discarded every server
/// error ApiX reported, for months, silently. These tests exercise what
/// **passes** at least as hard as what is dropped.
void main() {
  SentrySetupOptions optionsWith({
    bool filterNetworkNoise = true,
    String environment = 'production',
    int minTransactionDurationMs = 100,
    FutureOr<SentryEvent?> Function(SentryEvent, Hint)? customBeforeSend,
    FutureOr<SentryTransaction?> Function(SentryTransaction, Hint)?
        customBeforeSendTransaction,
  }) =>
      SentrySetupOptions(
        dsn: 'https://public@example.test/1',
        environment: environment,
        filterNetworkNoise: filterNetworkNoise,
        minTransactionDurationMs: minTransactionDurationMs,
        customBeforeSend: customBeforeSend,
        customBeforeSendTransaction: customBeforeSendTransaction,
      );

  SentryEvent eventFor(Object error) => SentryEvent(
        exceptions: [
          SentryException(
            type: error.runtimeType.toString(),
            value: error.toString(),
            throwable: error,
          ),
        ],
      );

  group('beforeSend — what must get through', () {
    test('a server error is sent', () {
      final result = SentrySetup.beforeSendForTesting(
        eventFor(const ServerException(message: 'boom', statusCode: 500)),
        Hint(),
        optionsWith(),
      );

      expect(result, isNotNull,
          reason: 'this is the category the filter used to swallow whole');
    });

    test('a business failure raised by a responseValidator is sent', () {
      final result = SentrySetup.beforeSendForTesting(
        eventFor(const ApiException(message: 'insufficient funds')),
        Hint(),
        optionsWith(),
      );

      expect(result, isNotNull);
    });

    test('an event with no exceptions at all is sent', () {
      final result = SentrySetup.beforeSendForTesting(
        SentryEvent(message: SentryMessage('a plain log')),
        Hint(),
        optionsWith(),
      );

      expect(result, isNotNull,
          reason: 'nothing here is network noise, so nothing may be dropped');
    });
  });

  group('beforeSend — what is dropped', () {
    test('an apix NetworkException is transport noise', () {
      final result = SentrySetup.beforeSendForTesting(
        eventFor(const ConnectionException(message: 'offline')),
        Hint(),
        optionsWith(),
      );

      expect(result, isNull);
    });

    test('filterNetworkNoise: false lets even that through', () {
      final result = SentrySetup.beforeSendForTesting(
        eventFor(const ConnectionException(message: 'offline')),
        Hint(),
        optionsWith(filterNetworkNoise: false),
      );

      expect(result, isNotNull,
          reason: 'the switch has to actually switch — a filter that ignores '
              'its own opt-out is the same defect one level up');
    });
  });

  group('beforeSend — the consumer callback', () {
    test('is consulted, and its refusal is honoured', () {
      var called = false;
      final result = SentrySetup.beforeSendForTesting(
        eventFor(const ServerException(message: 'boom', statusCode: 500)),
        Hint(),
        optionsWith(customBeforeSend: (event, hint) {
          called = true;
          return null;
        }),
      );

      expect(called, isTrue);
      expect(result, isNull);
    });

    test('never sees an event the noise filter already dropped', () {
      var called = false;
      SentrySetup.beforeSendForTesting(
        eventFor(const ConnectionException(message: 'offline')),
        Hint(),
        optionsWith(customBeforeSend: (event, hint) {
          called = true;
          return event;
        }),
      );

      expect(called, isFalse,
          reason: 'apix filters first; a consumer wanting the noise turns '
              'filterNetworkNoise off');
    });

    test('receives the real hint, not a fresh one', () {
      Hint? seen;
      final hint = Hint();
      hint.set('attachment-marker', 'present');

      SentrySetup.beforeSendForTesting(
        eventFor(const ServerException(message: 'boom', statusCode: 500)),
        hint,
        optionsWith(customBeforeSend: (event, h) {
          seen = h;
          return event;
        }),
      );

      expect(seen?.get('attachment-marker'), 'present');
    });
  });

  group('beforeSendTransaction — the duration rule', () {
    // The rule is tested through `isTooShort` rather than through a real
    // SentryTransaction: building one needs an `@internal` SentryTracer, and
    // importing sentry's internals here would couple this suite to a private
    // shape across the whole declared >=9.0.0 <10.0.0 range.
    final start = DateTime.utc(2026);

    test('a short transaction is dropped', () {
      expect(
        SentrySetup.isTooShort(
            start, start.add(const Duration(milliseconds: 10)), 100),
        isTrue,
      );
    });

    test('a long one is kept', () {
      expect(
        SentrySetup.isTooShort(
            start, start.add(const Duration(milliseconds: 500)), 100),
        isFalse,
      );
    });

    test('the boundary is not dropped', () {
      expect(
        SentrySetup.isTooShort(
            start, start.add(const Duration(milliseconds: 100)), 100),
        isFalse,
        reason: 'the threshold is a minimum, not an exclusion',
      );
    });

    test('the threshold is the configured one, not a constant', () {
      expect(
        SentrySetup.isTooShort(
            start, start.add(const Duration(milliseconds: 10)), 5),
        isFalse,
        reason: 'asserting only the default would leave the option itself '
            'unguarded — the exact shape of an inert setting',
      );
    });

    test('a transaction with no end timestamp is kept', () {
      expect(SentrySetup.isTooShort(start, null, 100), isFalse,
          reason: 'no measurable duration is not a reason to drop it');
    });
  });

  group('SentrySetupOptions — the factories set what they claim', () {
    test('production wires profiling and replay', () {
      final options =
          SentrySetupOptions.production(dsn: 'https://public@example.test/1');

      expect(options.tracesSampleRate, 0.5);
      expect(options.profilesSampleRate, 0.1);
      expect(options.replayOnErrorSampleRate, 1.0);
      expect(options.replaySessionSampleRate, 0.1);
      expect(options.environment, 'production');
    });

    test('development turns all of it off', () {
      final options =
          SentrySetupOptions.development(dsn: 'https://public@example.test/1');

      expect(options.tracesSampleRate, 0.0);
      expect(options.profilesSampleRate, 0.0);
      expect(options.replayOnErrorSampleRate, 0.0);
      expect(options.replaySessionSampleRate, 0.0);
    });

    test('sendDefaultPii is off unless asked for', () {
      expect(
        SentrySetupOptions.production(dsn: 'https://public@example.test/1')
            .sendDefaultPii,
        isFalse,
        reason: 'every app wiring SentrySetup used to ship headers, cookies '
            'and IP addresses without choosing to',
      );
    });
  });
}
