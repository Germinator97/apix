import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on what apix hands to a third-party error tracker.
///
/// This interceptor redacted `Authorization` and then sent the full URI, so a
/// token in a query parameter travelled in clear **past a redaction step that
/// had already run**. A half-applied redaction is worse than none: it reads as
/// complete, so nobody looks again.
void main() {
  ({
    ApiClient client,
    List<Map<String, dynamic>> contexts,
    List<Map<String, dynamic>> breadcrumbs,
    List<Object> exceptions,
  }) clientWith(
    ScriptedAdapter adapter, {
    ErrorTrackingConfig Function(ErrorTrackingConfig base)? tune,
  }) {
    final contexts = <Map<String, dynamic>>[];
    final breadcrumbs = <Map<String, dynamic>>[];
    final exceptions = <Object>[];

    var config = ErrorTrackingConfig(
      onError: (exception, {stackTrace, extra, tags}) async {
        exceptions.add(exception);
        if (extra != null) contexts.add(extra);
      },
      onBreadcrumb: breadcrumbs.add,
    );
    if (tune != null) config = tune(config);

    return (
      client: ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: adapter,
        errorTrackingConfig: config,
      ),
      contexts: contexts,
      breadcrumbs: breadcrumbs,
      exceptions: exceptions,
    );
  }

  ScriptedAdapter failing() => ScriptedAdapter(
        (options, i) => jsonResponse(
          {'message': 'boom', 'email': 'someone@example.com'},
          500,
        ),
      );

  /// Everything the tracker was handed, as one string. A leak anywhere in the
  /// payload is a leak, so asserting field by field would only prove the
  /// fields anyone thought to check.
  String everythingSent(
    List<Map<String, dynamic>> contexts,
    List<Map<String, dynamic>> breadcrumbs,
    List<Object> exceptions,
  ) =>
      [...contexts, ...breadcrumbs, ...exceptions].join(' | ');

  group('N9 — a query value never reaches the tracker', () {
    test('a token in the query is redacted everywhere it is rendered',
        () async {
      final wired = clientWith(failing());

      await expectLater(
        wired.client.get<dynamic>(
          '/reset',
          queryParameters: {'token': 'super-secret-value', 'lang': 'fr'},
        ),
        throwsA(isA<ApiException>()),
      );

      final sent =
          everythingSent(wired.contexts, wired.breadcrumbs, wired.exceptions);

      expect(sent, isNot(contains('super-secret-value')),
          reason: 'headers were redacted and the URI was not, so the '
              'redaction that ran gave a guarantee it did not hold');
      expect(sent, contains('[REDACTED]'));
    });

    test('the parameter names survive — the report stays usable', () async {
      final wired = clientWith(failing());

      await expectLater(
        wired.client.get<dynamic>('/reset', queryParameters: {'token': 'x'}),
        throwsA(isA<ApiException>()),
      );

      expect(
        everythingSent(wired.contexts, wired.breadcrumbs, wired.exceptions),
        contains('token='),
        reason: 'dropping the query outright looks safer and is worse: which '
            'parameters a failing request carried is most of the value of '
            'having the URL',
      );
    });

    test('the path is left readable, so the tracker can still group', () async {
      final wired = clientWith(failing());

      await expectLater(
        wired.client.get<dynamic>('/reset', queryParameters: {'token': 'x'}),
        throwsA(isA<ApiException>()),
      );

      expect(wired.contexts.single['url'], contains('/reset'));
      expect(wired.contexts.single['path'], '/reset');
    });

    test('a URL without a query is untouched', () async {
      final wired = clientWith(failing());

      await expectLater(
        wired.client.get<dynamic>('/plain'),
        throwsA(isA<ApiException>()),
      );

      expect(wired.contexts.single['url'], 'https://api.test/plain');
    });

    test('redactUrls: false restores the raw URL for those who choose it',
        () async {
      final wired = clientWith(
        failing(),
        tune: (base) => ErrorTrackingConfig(
          onError: base.onError,
          onBreadcrumb: base.onBreadcrumb,
          redactUrls: false,
        ),
      );

      await expectLater(
        wired.client.get<dynamic>('/reset', queryParameters: {'token': 'keep'}),
        throwsA(isA<ApiException>()),
      );

      expect(wired.contexts.single['url'], contains('token=keep'));
    });
  });

  group('N9 bis — captureResponseBody is off by default', () {
    test('a 500 body does not reach the tracker unasked', () async {
      final wired = clientWith(failing());

      await expectLater(
        wired.client.get<dynamic>('/x'),
        throwsA(isA<ApiException>()),
      );

      expect(
        wired.contexts.single.containsKey('response_body'),
        isFalse,
        reason: 'captureRequestBody defaulted to false on the line above while '
            'this one defaulted to true — and this is the body written by the '
            'server, which can carry fields the client never sent',
      );
    });

    test('turning it on still works', () async {
      final wired = clientWith(
        failing(),
        tune: (base) => ErrorTrackingConfig(
          onError: base.onError,
          onBreadcrumb: base.onBreadcrumb,
          captureResponseBody: true,
        ),
      );

      await expectLater(
        wired.client.get<dynamic>('/x'),
        throwsA(isA<ApiException>()),
      );

      expect(wired.contexts.single['response_body'], contains('boom'));
    });

    test('the status and the typed exception still get through', () async {
      final wired = clientWith(failing());

      await expectLater(
        wired.client.get<dynamic>('/x'),
        throwsA(isA<ApiException>()),
      );

      expect(wired.contexts.single['status_code'], 500);
      expect(wired.exceptions.single, isA<ServerException>(),
          reason: 'withholding the body must not withhold what the tracker '
              'groups by');
    });
  });
}
