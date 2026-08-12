import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on what leaves the package through the log sink.
///
/// 5.0 turned body logging off by default, which is only true if *every* path
/// asks. The error path did not, so the switch a consumer flips for privacy
/// governed the successful responses and left the failed ones through — on the
/// side where a body is most likely to describe the user who failed.
void main() {
  ApiClient clientWith(
    ScriptedAdapter adapter,
    LoggerConfig config,
  ) {
    return ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
      loggerConfig: config,
    );
  }

  ScriptedAdapter failing() => ScriptedAdapter(
        (options, i) => jsonResponse(
          {'message': 'refused', 'email': 'someone@example.com'},
          500,
        ),
      );

  LogEntry errorEntryOf(List<LogEntry> entries) =>
      entries.firstWhere((entry) => entry.level == LogLevel.error);

  group('N2 — logResponseBody governs the error path too', () {
    test('an error body is withheld when bodies are off', () async {
      final entries = <LogEntry>[];
      final client = clientWith(
        failing(),
        LoggerConfig(logResponseBody: false, logHandler: entries.add),
      );

      await expectLater(
        client.get<dynamic>('/x'),
        throwsA(isA<ApiException>()),
      );

      expect(
        errorEntryOf(entries).body,
        isNull,
        reason: 'the error path used to hand the body over unconditionally, '
            'so a 500 carrying personal data reached the sink even under '
            'LoggerConfig.minimal()',
      );
    });

    test('the default config withholds it — 5.0 says bodies are off', () async {
      final entries = <LogEntry>[];
      final client =
          clientWith(failing(), LoggerConfig(logHandler: entries.add));

      await expectLater(
        client.get<dynamic>('/x'),
        throwsA(isA<ApiException>()),
      );

      expect(errorEntryOf(entries).body, isNull);
    });

    test('LoggerConfig.minimal() withholds it', () async {
      final entries = <LogEntry>[];
      final client = clientWith(
        failing(),
        LoggerConfig.minimal().copyWith(logHandler: entries.add),
      );

      await expectLater(
        client.get<dynamic>('/x'),
        throwsA(isA<ApiException>()),
      );

      expect(errorEntryOf(entries).body, isNull);
    });

    // The other half. Making the emit conditional is exactly the kind of fix
    // that cuts too much: a consumer who asked for bodies must still get the
    // one that matters most.
    test('an error body IS handed over when bodies are on', () async {
      final entries = <LogEntry>[];
      final client = clientWith(
        failing(),
        LoggerConfig(logResponseBody: true, logHandler: entries.add),
      );

      await expectLater(
        client.get<dynamic>('/x'),
        throwsA(isA<ApiException>()),
      );

      final body = errorEntryOf(entries).body as Map<String, dynamic>;
      expect(body['message'], 'refused');
    });

    test('everything else about the error entry is unchanged', () async {
      final entries = <LogEntry>[];
      final client = clientWith(
        failing(),
        LoggerConfig(logResponseBody: false, logHandler: entries.add),
      );

      await expectLater(
        client.get<dynamic>('/x'),
        throwsA(isA<ApiException>()),
      );

      final entry = errorEntryOf(entries);
      expect(entry.statusCode, 500,
          reason: 'withholding the body must not '
              'quietly withhold the reason the request failed');
      expect(entry.method, 'GET');
      expect(entry.url, contains('/x'));
      expect(entry.error, isNotNull);
    });
  });
}
