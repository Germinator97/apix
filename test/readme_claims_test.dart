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
  late String changelog;
  late String factorySource;

  setUpAll(() {
    readme = File('README.md').readAsStringSync();
    pubspec = File('pubspec.yaml').readAsStringSync();
    changelog = File('CHANGELOG.md').readAsStringSync();
    factorySource =
        File('lib/src/client/api_client_factory.dart').readAsStringSync();
  });

  String declaredVersion() {
    final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec)
        ?.group(1);
    expect(declared, isNotNull, reason: 'no version: line in pubspec.yaml');
    return declared!;
  }

  group('README claims', () {
    // The project rule says three places move together — pubspec, the README
    // install snippet, and the CHANGELOG section title — and that this test
    // falls if only two of them do. It read exactly two files, so forgetting
    // the CHANGELOG heading passed in green: a rule guarded by a test that did
    // not guard it, which is worse than an unguarded rule because nobody
    // re-checks it by hand.
    test('the CHANGELOG has a section for the version being shipped', () {
      final declared = declaredVersion();

      final titles = RegExp(r'^##\s+(\S+)', multiLine: true)
          .allMatches(changelog)
          .map((match) => match.group(1)!)
          .toList();

      expect(titles, isNotEmpty,
          reason: 'no "## x.y.z" heading found in CHANGELOG.md — update this '
              'regex, do not delete the test');
      expect(
        titles.first,
        declared,
        reason: 'pubspec says $declared and the newest CHANGELOG section is '
            '${titles.first}. A consumer opening the changelog to ask "does '
            'this break me?" finds nothing about the version they are '
            'installing.',
      );
    });

    test('the install snippet resolves to the published version', () {
      final declared = declaredVersion();

      final advertised =
          RegExp(r'apix:\s*\^(\S+)').firstMatch(readme)?.group(1);
      expect(
        advertised,
        isNotNull,
        reason: 'no "apix: ^x.y.z" install snippet found in README — update '
            'this regex if the snippet was reworded',
      );

      // Caret compatibility, not equality. `^4.0.0` correctly installs any
      // later 4.x, so demanding equality would fail on every patch release and
      // push toward editing the README for no reader-visible reason — a guard
      // that cries wolf gets silenced. What must never happen is the snippet
      // pointing somewhere nobody can reach: a different major, or a version
      // ahead of what is published.
      final want = advertised!.split('.').map(int.parse).toList();
      final have = declared.split('.').map(int.parse).toList();

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

    // Each of these shipped answering a specific complaint. A feature absent
    // from the README is one nobody will find.
    //
    // ⚠️ This list is **per release, and has to move with the version**. It sat
    // frozen at "every 4.0.0 addition" through the whole 5.0 cycle, so three
    // APIs shipped in 5.0 — `forceRevalidate()`, `MultipartReplayException`,
    // `CacheBodyEncoding` — reached zero mentions in the README, in
    // `example/example.dart` and in the demo app, guarded by a test whose own
    // comment says a feature absent from the README is one nobody will find.
    // A relevé that outlives what it describes stops being a guard and becomes
    // a permission.
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

    test('every 5.0.0 addition is mentioned', () {
      const additions = {
        'varyHeaders': 'B1 — cache entries scoped to the caller',
        'forceRevalidate': 'a conditional refresh nothing could trigger',
        'MultipartReplayException': 'B4 — a replay that cannot rebuild a body',
        'CacheBodyEncoding': 'M7 — a hit keeps the type it had',
        'cacheInterceptor': 'reaching the invalidation API',
        'strictContentType': 'captive portals',
        'responseValidator': 'M8 — business failures dressed as 200',
        'isStale': 'knowing the body is past its TTL',
        'onCacheHit': 'a hit no observer could see',
        'onCacheError': 'a storage failure nobody could learn about',
        'evictExpired': 'the sweep getCacheKeys used to do silently',
        'redactUrls': 'query values leaving for the tracker',
        'onSendProgress': 'progress on the typed methods',
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

    // The generalisation of the two lists above, and the reason they keep
    // going stale: a per-release relevé has to be extended by hand, so it
    // records the releases someone remembered. This one is derived from the
    // barrel, so it covers what is exported rather than what was recalled.
    //
    // Scoped to classes and enums. A typedef is a signature you write as a
    // lambda, and an extension is a name you never write at all — demanding
    // that `NoRetryExtension` appear in prose would train the reader to ignore
    // this test, which is how a guard gets silenced.
    test('every exported class and enum is named in the README', () {
      final barrel = File('lib/apix.dart').readAsStringSync();
      final exported = RegExp(r"^export '(src/[^']+)';", multiLine: true)
          .allMatches(barrel)
          .map((match) => match.group(1)!)
          .toList();

      expect(exported, isNotEmpty,
          reason: 'no relative export found in lib/apix.dart — this parsing is '
              'stale, not the barrel');

      final undocumented = <String>[];
      for (final relative in exported) {
        final source = File('lib/$relative')
            .readAsStringSync()
            .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '');
        final declared = [
          ...RegExp(r'^(?:abstract |final |sealed |base )*class (\w+)',
                  multiLine: true)
              .allMatches(source),
          ...RegExp(r'^enum (\w+)', multiLine: true).allMatches(source),
        ].map((match) => match.group(1)!).where((n) => !n.startsWith('_'));

        undocumented.addAll(declared.where((name) => !readme.contains(name)));
      }

      // Equality, not containment. A type that stops being documented has to
      // fail here, and so does one that starts being documented without this
      // list shrinking — otherwise the exception list outlives its reasons and
      // becomes a standing permission, which is exactly what happened to the
      // "every 4.0.0 addition" relevé above.
      expect(
        undocumented.toSet(),
        {
          // Returned by CacheInterceptor's internal parsing. A consumer never
          // constructs one and never receives one.
          'CacheControlHeader',
          // Wired by CacheInterceptor and DeduplicationInterceptor for you;
          // reachable, but there is nothing a consumer does with it directly.
          'RequestDeduplicator',
        },
        reason: 'a type a consumer can be handed, and cannot find in the '
            'README, is a type they will not use — or will use from its name '
            'alone. Document it, or justify it here.',
      );
    });

    // The counterpart, and the half that was missing. Containment lets the
    // list survive what it describes; equality makes a removed API fail here
    // too, which is the only way a relevé keeps meaning anything.
    test('the README documents no per-request cache key apix does not read',
        () {
      final documented = RegExp(r"extra:\s*\{\s*'(\w+)'")
          .allMatches(readme)
          .map((match) => match.group(1)!)
          .toSet();

      expect(
        documented,
        isNotEmpty,
        reason: 'no documented extra key found — this parsing is stale, not '
            'the README',
      );

      // `cacheStrategy` is the only bare-string key the interceptor reads;
      // everything else goes through a named extension. The README used to
      // show `cacheTtl` and `forceRefresh`, neither of which has ever existed
      // in lib/ — quietly ignored, which is the exact failure mode of an
      // option that looks set.
      expect(
        documented,
        {'cacheStrategy'},
        reason: 'a per-request extra key in the README must be one apix '
            'actually reads',
      );
    });
  });
}
