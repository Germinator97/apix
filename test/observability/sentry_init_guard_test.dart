import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards that crash reporting cannot stop the app it reports on.
///
/// `SentryFlutter.init` runs the app itself, from inside. Anything that threw
/// before it reached that point — a malformed DSN, a plugin missing on a
/// platform, a `configureOptions` touching an option the installed SDK dropped
/// — took the whole application down with it. A side channel that can prevent
/// startup is a worse liability than the reports it collects.
///
/// Two properties have to hold at once, and each is easy to satisfy while
/// breaking the other.
void main() {
  setUp(SentrySetup.resetForTesting);
  tearDown(SentrySetup.resetForTesting);

  group('N11 — the app starts whatever initialization does', () {
    test('it starts when init throws before running it', () async {
      var started = 0;

      await SentrySetup.guardedStart(
        appRunner: () async => started++,
        initialize: (_) async => throw StateError('invalid DSN'),
      );

      expect(started, 1, reason: 'no app is worse than no crash reporting');
    });

    test('it starts exactly once when init throws AFTER running it', () async {
      var started = 0;

      await SentrySetup.guardedStart(
        appRunner: () async => started++,
        initialize: (runner) async {
          await runner();
          throw StateError('failed on something later');
        },
      );

      expect(
        started,
        1,
        reason: 'the other half: SentryFlutter.init may well have started the '
            'app before failing, and a second runApp is not a recovery',
      );
    });

    test('it starts exactly once on the nominal path', () async {
      var started = 0;

      await SentrySetup.guardedStart(
        appRunner: () async => started++,
        initialize: (runner) => runner(),
      );

      expect(started, 1);
    });

    test('an initializer that never runs the app still starts it', () async {
      var started = 0;

      await SentrySetup.guardedStart(
        appRunner: () async => started++,
        initialize: (_) async {},
      );

      expect(started, 1,
          reason: 'the contract is that the app runs, not that something else '
              'remembered to run it');
    });
  });

  group('N11 bis — the retry the flag exists to allow', () {
    test('a failed initialization does not mark the setup as done', () async {
      await SentrySetup.guardedStart(
        appRunner: () async {},
        initialize: (_) async => throw StateError('boom'),
      );

      expect(
        SentrySetup.isInitialized,
        isFalse,
        reason: 'a flag left standing after a failure makes the next, '
            'legitimate attempt a silent no-op — an app reporting nothing '
            'looks exactly like an app with nothing to report',
      );
    });

    test('a successful one does', () async {
      await SentrySetup.guardedStart(
        appRunner: () async {},
        initialize: (runner) => runner(),
      );

      expect(SentrySetup.isInitialized, isTrue);
    });
  });

  group('N11 ter — the paths that skip initialization entirely', () {
    test('a disabled config still runs the app', () async {
      var started = 0;

      await SentrySetup.init(
        options: const SentrySetupOptions(
          dsn: 'https://public@example.test/1',
          environment: 'test',
          enabled: false,
        ),
        appRunner: () async => started++,
      );

      expect(started, 1);
      expect(SentrySetup.isInitialized, isFalse);
    });
  });
}
