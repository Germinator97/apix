@TestOn('vm')
library;

import 'dart:io';

import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the section of the CHANGELOG that a consumer acts on: the defaults.
///
/// A consumer asked for "the rule rather than the fix" after noticing
/// that a table addressed to consumers had stopped following the corrections it
/// described. Their reasoning is the one already written into
/// `readme_claims_test`: a relevé that outlives what it describes stays green
/// while guarding nothing, and this one has no test and looks complete.
///
/// So this file derives the check instead of repeating the list. Every default
/// the changelog announces is read back off the code, by **equality** in both
/// directions:
///
/// * a default that changes without the changelog moving fails here;
/// * a changelog line that describes a default the code does not have fails
///   here too — which is the direction that caught nothing before, because a
///   stale line reads exactly like a current one.
void main() {
  late String changelog;
  late String currentSection;

  setUpAll(() {
    changelog = File('CHANGELOG.md').readAsStringSync();
    final start = changelog.indexOf('## 5.0.0');
    final end = changelog.indexOf('\n## ', start + 1);
    currentSection = changelog.substring(start, end == -1 ? null : end);
  });

  /// The privacy-facing defaults, paired with the value the code actually has.
  ///
  /// Named by the exact string the changelog uses, so a reworded entry fails
  /// loudly rather than silently ceasing to be checked.
  Map<String, ({String announced, Object actual})> defaults() => {
        '`SentrySetupOptions.sendDefaultPii` → **`false`**': (
          announced: 'false',
          actual: const SentrySetupOptions(dsn: 'x', environment: 'y')
              .sendDefaultPii,
        ),
        '`ErrorTrackingConfig.captureResponseBody` → **`false`**': (
          announced: 'false',
          actual: const ErrorTrackingConfig().captureResponseBody,
        ),
        '`ErrorTrackingConfig.redactUrls` → **`true`**': (
          announced: 'true',
          actual: const ErrorTrackingConfig().redactUrls,
        ),
        '`LoggerConfig` logs no request or response body, error path included':
            (
          announced: 'false',
          actual: const LoggerConfig().logResponseBody &&
              const LoggerConfig().logRequestBody,
        ),
      };

  group('the changelog and the code agree on every announced default', () {
    defaults().forEach((claim, pair) {
      test(claim, () {
        expect(
          currentSection,
          contains(claim),
          reason: 'the 5.0.0 section no longer contains this sentence. If it '
              'was reworded, update the key here — if the default was dropped, '
              'the consumer-facing announcement went with it.',
        );
        expect(
          pair.actual.toString(),
          pair.announced,
          reason: 'the changelog announces "$claim" and the code disagrees',
        );
      });
    });
  });

  group('the section keeps the parts a consumer acts on', () {
    test('it says what breaks at build time', () {
      expect(
        currentSection,
        contains('Nothing breaks your build'),
        reason: 'the first question before a major, and the only one with a '
            'yes/no answer',
      );
      expect(currentSection, contains('migration_4_1_0_compiles_test'),
          reason: 'the claim has to point at what checks it');
    });

    test('it warns where a fix removes information', () {
      expect(
        currentSection,
        contains('remove a field you may be diagnosing from'),
        reason: 'two of the tightened defaults make Sentry tickets thinner. A '
            'consumer who is not told will look for the fault in their API.',
      );
    });

    test('it names the error classes behind the rise in events', () {
      for (final named in [
        'broken sessions',
        'responseValidator',
        'cacheOnly'
      ]) {
        expect(
          currentSection,
          contains(named),
          reason: 'an unexplained doubling of Sentry events reads as a '
              'regression, and gets rolled back',
        );
      }
    });

    test('LoggerConfig.trace() really is the escape hatch it points at', () {
      expect(
          currentSection, contains('`LoggerConfig.trace()` still keeps both'));
      final trace = LoggerConfig.trace();
      expect(trace.logRequestBody, isTrue);
      expect(trace.logResponseBody, isTrue);
    });

    test('the changelog mentions no version that was never released', () {
      // A version numbered while fixes are in flight and then dropped leaves a
      // heading nobody can install, and sends readers looking for it on pub.dev.
      expect(
        changelog,
        reason: 'the release went 4.1.0 → 5.0.0, with nothing in between',
      );
    });
  });
}
