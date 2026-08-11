import 'dart:io';

import 'package:apix/apix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_harness.dart';

/// Regression guards on what actually leaves the device for a multipart
/// request.
///
/// Every defect here produced a request the server happily answered `200` to.
/// The only way to see them is to inspect the `FormData` the adapter received,
/// which is what these tests do.
void main() {
  late Directory tempDir;
  late File avatar;
  late File attachment;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('apix_multipart_regression');
    avatar = File('${tempDir.path}/avatar.png')..writeAsStringSync('img');
    attachment = File('${tempDir.path}/report.pdf')..writeAsStringSync('pdf');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Sends [data] and returns the `FormData` that reached the adapter.
  Future<FormData> send(Map<String, dynamic> data) async {
    final adapter =
        ScriptedAdapter((options, i) => jsonResponse({'ok': 1}, 200));
    final client = ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
    );
    await client.post<dynamic>('/upload', data: data);
    return adapter.seen.single.data as FormData;
  }

  Map<String, String> fieldsOf(FormData form) =>
      {for (final entry in form.fields) entry.key: entry.value};

  List<String> fileKeysOf(FormData form) =>
      form.files.map((entry) => entry.key).toList();

  group('B3 — nothing is dropped on the way to the wire', () {
    test('a nested map keeps its siblings and its nesting', () async {
      final form = await send({
        'user': {'avatar': avatar, 'name': 'John'},
      });

      expect(fileKeysOf(form), ['user[avatar]'],
          reason: 'the outer key must survive, not be flattened away');
      expect(fieldsOf(form), containsPair('user[name]', 'John'),
          reason: 'a non-file sibling of a file must still be sent');
    });

    test('a file nested two levels deep still reaches the wire', () async {
      final form = await send({
        'a': {
          'b': {'file': attachment},
        },
      });

      expect(fileKeysOf(form), ['a[b][file]'],
          reason: 'this used to send an empty body and return 200');
    });

    test('a mixed list keeps its non-file entries', () async {
      final form = await send({
        'items': [avatar, 'a-caption'],
      });

      expect(form.files, hasLength(1));
      expect(fieldsOf(form).values, contains('a-caption'),
          reason: 'the caption used to be dropped silently');
    });

    test('several files under one key keep the repeated-key convention',
        () async {
      final form = await send({
        'files': [avatar, attachment],
      });

      expect(fileKeysOf(form), ['files', 'files'],
          reason: "dio's ListFormat.multi repeats the bare key for a flat "
              'list, which is what backends expect for files[]');
    });

    test('a plain map with no files is untouched', () async {
      final form = await send({'name': 'John', 'file': avatar});

      expect(fieldsOf(form), containsPair('name', 'John'));
      expect(fileKeysOf(form), ['file']);
    });

    test('deeply nested scalars survive alongside a deep file', () async {
      final form = await send({
        'meta': {
          'owner': {'id': 42, 'label': 'ops'},
          'doc': attachment,
        },
      });

      expect(fileKeysOf(form), ['meta[doc]']);
      expect(fieldsOf(form), containsPair('meta[owner][id]', '42'));
      expect(fieldsOf(form), containsPair('meta[owner][label]', 'ops'));
    });
  });
}
