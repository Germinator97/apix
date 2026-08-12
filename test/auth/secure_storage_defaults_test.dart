@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Guards the one option that decides whether apix's recovery runs at all.
///
/// `AndroidOptions` defaults to `resetOnError: true`, and under that default
/// the Android plugin deletes unreadable data and retries the read **itself**.
/// Measured on an Android 16 emulator: the read still answers `null`, so every
/// contract test stays green — and `onBeforeRecoveryDelete` never fires, while
/// the credential is destroyed anyway. Nothing about that failure is visible
/// from Dart. Restoring the plugin's default would silently disconnect the
/// channel a consumer asked for, and no other test in this suite would
/// notice, because they all inject their own storage.
///
/// The real assertion is behavioural and lives on a device —
/// `apix_example_app/integration_test/secure_storage_device_test.dart` stages a
/// genuine decryption failure and checks the channel actually announces. This
/// file is the cheap structural net under it: the device probe needs an
/// emulator and a run, this one fails in the ordinary suite.
///
/// It reads the source rather than the object because `SecureStorageService`
/// keeps its `FlutterSecureStorage` private, so the option cannot be observed
/// through the public API. That makes it a pattern test, with the failure mode
/// pattern tests have: it must prove it found something before it asserts
/// anything about it.
void main() {
  late String source;

  setUpAll(() {
    source =
        File('lib/src/auth/secure_storage_service.dart').readAsStringSync();
  });

  /// Every place the service builds Android options, with the code that follows
  /// it — enough to cover the argument list, not so much that two sites merge.
  List<String> androidOptionSites() {
    // Requires the opening parenthesis, so the prose in the dartdoc that names
    // `AndroidOptions` without calling it is not mistaken for a call site.
    final pattern = RegExp(r'AndroidOptions(\.biometric)?\(');
    return [
      for (final match in pattern.allMatches(source))
        source.substring(match.start, math.min(source.length, match.end + 300)),
    ];
  }

  test('the service builds Android options in exactly two places', () {
    // By equality, not by inclusion: a third constructor added later must fail
    // here and be decided on, rather than inheriting the plugin's default in
    // silence. If this is what broke, add the new site to the expectation —
    // after checking it passes resetOnError: false.
    expect(
      androidOptionSites(),
      hasLength(2),
      reason: 'expected the plain constructor and withBiometrics(). If neither '
          'is found, this guard has stopped guarding: the constructors were '
          'renamed or moved, and every assertion below became vacant.',
    );
  });

  test('both opt out of the plugin repairing corruption behind apix', () {
    for (final site in androidOptionSites()) {
      expect(
        site,
        contains('resetOnError: false'),
        reason:
            'this site lets the plugin delete unreadable data and retry on its '
            'own. The read still answers null, so nothing here would go red — '
            'but apix never sees the failure, onBeforeRecoveryDelete stays '
            'silent, and a credential is destroyed with nobody told. Measured '
            'in secure_storage_device_test.dart, which is where to look before '
            'changing this back.',
      );
    }
  });

  test('the dartdoc no longer claims withBiometrics degrades silently', () {
    // It does not degrade: on a device with no credential it raises
    // BIOMETRIC_UNAVAILABLE. The opposite claim stood in this file for months,
    // measured by a probe that ran fourth in its file and could not arm —
    // the plugin builds its cipher once per process, on the first call.
    expect(
      source,
      contains('BIOMETRIC_UNAVAILABLE'),
      reason: 'the factory documents what the platform actually answers, and '
          'the verbatim message is the evidence',
    );
    expect(
      source,
      isNot(contains('degrades silently')),
      reason: 'that measurement was an artefact of a probe that never armed. '
          'If it is back, it needs a device run behind it — one file, one '
          'process, one first initialisation.',
    );
  });
}
