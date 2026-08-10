@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the claims the README makes *about the code*, which nothing else
/// checks: a stale count or version renders exactly as well as a correct one,
/// and neither the analyzer nor any widget test can see the difference.
///
/// Every assertion here first proves its pattern was found. A regex that stops
/// matching after a harmless rewording would otherwise leave the test green
/// while it silently guards nothing.
void main() {
  late String readme;
  late String pubspec;
  late String factorySource;

  setUpAll(() {
    readme = File('README.md').readAsStringSync();
    pubspec = File('pubspec.yaml').readAsStringSync();
    factorySource =
        File('lib/src/client/api_client_factory.dart').readAsStringSync();
  });

  group('README claims', () {
    test('the install snippet resolves to the published version', () {
      final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec)
          ?.group(1);
      expect(declared, isNotNull, reason: 'no version: line in pubspec.yaml');

      final advertised =
          RegExp(r'apix:\s*\^(\S+)').firstMatch(readme)?.group(1);
      expect(
        advertised,
        isNotNull,
        reason: 'no "apix: ^x.y.z" install snippet found in README — update '
            'this regex if the snippet was reworded',
      );

      // Caret compatibility, not equality. `^4.0.0` correctly installs 4.0.1,
      // so demanding equality would fail on every patch release and push
      // toward editing the README for no reader-visible reason — a guard that
      // cries wolf gets silenced. What must never happen is the snippet
      // pointing somewhere nobody can reach: a different major, or a version
      // ahead of what is published.
      final want = advertised!.split('.').map(int.parse).toList();
      final have = declared!.split('.').map(int.parse).toList();

      expect(
        want[0],
        equals(have[0]),
        reason: 'README advertises ^$advertised, package is $declared — a '
            'different major resolves to something else entirely',
      );
      expect(
        want[1] * 1000 + want[2],
        lessThanOrEqualTo(have[1] * 1000 + have[2]),
        reason: 'README advertises ^$advertised, ahead of the published '
            '$declared — nobody can install that',
      );
    });

    // The count is prose, so it cannot be interpolated. Derive the check
    // instead: whichever number is written has to match reality.
    test('the advertised number of config blocks matches the factory', () {
      final claim =
          RegExp(r'configuration with (\d+) optional').firstMatch(readme);
      expect(
        claim,
        isNotNull,
        reason: 'the "configuration with N optional…" sentence moved or was '
            'reworded — update this regex, do not delete the test',
      );

      final signature = factorySource.substring(
        factorySource.indexOf('static ApiClient fromConfig'),
      );
      final params = signature.substring(0, signature.indexOf(') {'));
      final actual =
          RegExp(r'^\s*\w+Config\?\s', multiLine: true).allMatches(params);

      expect(
        actual,
        isNotEmpty,
        reason: 'no *Config? parameters found in fromConfig — the parsing '
            'here is broken, not the README',
      );
      expect(
        int.parse(claim!.group(1)!),
        equals(actual.length),
        reason: 'the README advertises ${claim.group(1)} config blocks, '
            'ApiClientFactory.fromConfig takes ${actual.length}',
      );
    });

    // Each of these shipped in 4.0.0 answering a specific integration
    // complaint. A feature absent from the README is one nobody will find.
    test('every 4.0.0 addition is mentioned', () {
      const additions = {
        'errorCodeKey': 'application error code',
        'TooManyRequestsException': 'typed 429',
        'DeduplicationConfig': 'deduplication without a cache',
        'jitter': 'spread backoff',
        'onRetry': 'observable retries',
        'TracingConfig': 'performance spans',
        'EncryptedCacheStorage': 'encrypted cache',
        'ResponseType': 'completed dio barrel',
        'package:apix/testing.dart': 'testing entry point',
      };

      final missing = additions.entries
          .where((e) => !readme.contains(e.key))
          .map((e) => '${e.key} (${e.value})')
          .toList();

      expect(
        missing,
        isEmpty,
        reason: 'shipped but undocumented: ${missing.join(', ')}',
      );
    });
  });
}
