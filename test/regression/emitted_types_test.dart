@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards on public values the package *declares* against the ones it actually
/// *constructs*.
///
/// A type or an enum value that is exported, documented and never built turns
/// every `on X catch` and every `case X` at a call site into a branch that
/// cannot be taken. Nothing detects it: the symbol resolves, the analyzer is
/// happy, and its own unit test passes — `expect(built.operation, clear)` is
/// true of an instance the test built itself.
///
/// Only a grep of the **construction sites** sees it, which is what these tests
/// automate. They read `lib/` as text on purpose: the question is not what the
/// type system allows, it is what this source ever writes down.
void main() {
  late String libSource;

  /// Removes doc comments, line comments and block comments.
  ///
  /// Load-bearing, and learned the hard way while writing this file: the first
  /// version scanned the raw source and matched the sentence in
  /// `token_provider_exception.dart` that *documents* the value it was meant to
  /// prove absent. A guard on construction sites must read code, never prose —
  /// otherwise describing a symbol is enough to satisfy the test that it exists.
  String stripComments(String source) {
    return source
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
  }

  setUpAll(() {
    final buffer = StringBuffer();
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        buffer.writeln(stripComments(entity.readAsStringSync()));
      }
    }
    libSource = buffer.toString();
  });

  /// Every `TokenProviderOperation.<value>` written as code in `lib/`.
  Set<String> operationsNamedInLib() {
    return RegExp(r'TokenProviderOperation\.(\w+)')
        .allMatches(libSource)
        .map((match) => match.group(1)!)
        .toSet();
  }

  group('N4 — TokenProviderOperation says which values apix produces', () {
    test('apix constructs read and write, and nothing else', () {
      final named = operationsNamedInLib();

      expect(
        named,
        isNotEmpty,
        reason: 'no TokenProviderOperation reference found in lib/ — this test '
            'is broken, not the code',
      );

      // Equality, not containment: a value that gains a producer must update
      // this list, and so must a value that loses one. A `contains` check would
      // survive both and quietly stop guarding.
      expect(
        named,
        {'read', 'write'},
        reason: 'apix produces exactly these. If a third appears, its dartdoc '
            'in token_provider_exception.dart still says otherwise, and every '
            'consumer switch written from that doc is now wrong.',
      );
    });

    test('clear is documented as never produced by apix', () {
      final source =
          File('lib/src/auth/token_provider_exception.dart').readAsStringSync();
      final clearDoc = source.substring(
        source.indexOf('/// A clear failed'),
        source.indexOf('  clear,'),
      );

      expect(
        clearDoc,
        contains('Never produced by apix'),
        reason: 'the guard above is only useful if the value it describes says '
            'so where a consumer reads it',
      );
    });
  });

  group('N4 bis — every exported exception subtype has a producer', () {
    /// The exception types apix documents as things a caller can catch. Each
    /// must appear as a *constructor call* somewhere in `lib/`, not merely as a
    /// declaration — otherwise the `on X catch` the docs show is dead.
    const catchable = [
      'TimeoutException',
      'ConnectionException',
      'NetworkException',
      'UnauthorizedException',
      'ForbiddenException',
      'NotFoundException',
      'TooManyRequestsException',
      'ClientException',
      'ServerException',
      'HttpException',
      'ParsingException',
      'UnexpectedContentTypeException',
      'MultipartReplayException',
      'TokenProviderException',
      'CacheException',
      'AuthException',
      'HttpTrackingException',
    ];

    for (final type in catchable) {
      test('$type is constructed somewhere in lib/', () {
        // `Type(` or `const Type(` — a construction, never a declaration
        // (`class Type extends`) and never a type annotation.
        final constructed = RegExp('(?<![\\w.])$type\\(').hasMatch(libSource);

        expect(
          constructed,
          isTrue,
          reason: '$type is exported and documented as catchable, but nothing '
              'in lib/ ever builds one. Every `on $type catch` a consumer '
              'writes from the docs would fall through in silence.',
        );
      });
    }
  });
}
