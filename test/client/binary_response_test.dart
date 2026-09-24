import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:apix/src/http/content_disposition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BinaryResponse', () {
    BinaryResponse withHeaders(Map<String, List<String>> headers) =>
        BinaryResponse(
          bytes: Uint8List.fromList([1, 2, 3]),
          statusCode: 200,
          headers: headers,
        );

    test('header() is case-insensitive', () {
      final response = withHeaders({
        'X-Missing-Items': ['2026-07'],
      });

      expect(response.header('x-missing-items'), '2026-07');
      expect(response.header('X-MISSING-ITEMS'), '2026-07');
      expect(response.header('absent'), isNull);
    });

    test('a repeated header reads as its values joined, as a cache hit does',
        () {
      final response = withHeaders({
        'x-tag': ['a', 'b'],
      });

      expect(response.header('x-tag'), 'a, b');
    });

    test('names that differ only by case are merged, lowercased', () {
      final response = withHeaders({
        'X-Tag': ['a'],
        'x-tag': ['b'],
      });

      expect(response.headers.keys, ['x-tag']);
      expect(response.headers['x-tag'], ['a', 'b']);
    });

    test('headers cannot be modified', () {
      final response = withHeaders({
        'x-tag': ['a'],
      });

      expect(() => response.headers['x-new'] = ['b'], throwsUnsupportedError);
      expect(() => response.headers['x-tag']!.add('c'), throwsUnsupportedError);
    });

    test('contentType is the first Content-Type, parameters included', () {
      expect(
        withHeaders({
          'content-type': ['application/pdf; charset=binary', 'text/html'],
        }).contentType,
        'application/pdf; charset=binary',
      );
      expect(withHeaders({}).contentType, isNull);
    });

    test('isEmpty is true only for an empty body', () {
      expect(
          BinaryResponse(bytes: Uint8List(0), statusCode: 204).isEmpty, isTrue);
      expect(withHeaders({}).isEmpty, isFalse);
    });

    test('toString never prints the bytes', () {
      final response = BinaryResponse(
        bytes: Uint8List(5 * 1024 * 1024),
        statusCode: 200,
        headers: {
          'content-type': ['application/pdf'],
        },
      );

      expect(response.toString(),
          'BinaryResponse(200, application/pdf, 5242880 bytes)');
    });

    test('fileName reads Content-Disposition', () {
      expect(
        withHeaders({
          'Content-Disposition': ['attachment; filename="report.pdf"'],
        }).fileName,
        'report.pdf',
      );
      expect(withHeaders({}).fileName, isNull);
    });
  });

  group('fileNameFromContentDisposition', () {
    final cases = <String, String?>{
      // The two spellings, and their priority.
      'attachment; filename="report.pdf"': 'report.pdf',
      'attachment; filename=report.pdf': 'report.pdf',
      "attachment; filename=\"plain.pdf\"; filename*=UTF-8''r%C3%A9sum%C3%A9.pdf":
          'résumé.pdf',
      "attachment; filename*=UTF-8''r%C3%A9sum%C3%A9.pdf; filename=\"plain.pdf\"":
          'résumé.pdf',
      "attachment; filename*=utf-8'en'na%C3%AFve.pdf": 'naïve.pdf',
      "attachment; filename*=ISO-8859-1''caf%E9.pdf": 'café.pdf',
      "attachment; filename*=\"UTF-8''quoted.pdf\"": 'quoted.pdf',
      // A filename* that does not decode falls back to filename.
      "attachment; filename*=UTF-8''bad%ZZname.pdf; filename=\"fallback.pdf\"":
          'fallback.pdf',
      "attachment; filename*=UTF-8''cut%E; filename=\"fallback.pdf\"":
          'fallback.pdf',
      "attachment; filename*=UTF-8''%FF.pdf; filename=\"fallback.pdf\"":
          'fallback.pdf',
      "attachment; filename*=KOI8-R''x.pdf; filename=\"fallback.pdf\"":
          'fallback.pdf',
      "attachment; filename*=UTF-8''%2B1.pdf": '+1.pdf',
      // Quoting.
      r'attachment; filename="a \"quoted\" name.pdf"': 'a "quoted" name.pdf',
      'attachment; filename="a;b.pdf"; size=12': 'a;b.pdf',
      'attachment; FILENAME="upper.pdf"': 'upper.pdf',
      'attachment; creation-date; filename="after-a-bare-token.pdf"':
          'after-a-bare-token.pdf',
      // Raw UTF-8 in filename, as dart:io delivers it: one char per byte.
      'attachment; filename="rÃ©sumÃ©.pdf"': 'résumé.pdf',
      // A genuine Latin-1 name is not valid UTF-8 and is kept.
      'attachment; filename="caf${String.fromCharCode(0xE9)}.pdf"': 'café.pdf',
      // Sanitised: the server does not choose where the file lands.
      'attachment; filename="../../etc/passwd"': 'passwd',
      r'attachment; filename="C:\\Windows\\evil.dll"': 'evil.dll',
      'attachment; filename="dir/"': null,
      'attachment; filename=".."': null,
      'attachment; filename="."': null,
      'attachment; filename=""': null,
      'attachment; filename="   "': null,
      'attachment; filename="bell${String.fromCharCode(7)}.pdf"': 'bell.pdf',
      'attachment; filename="txt${String.fromCharCode(0x202E)}fdp.exe"':
          'txtfdp.exe',
      'attachment; filename="a${String.fromCharCode(0x2066)}b.pdf"': 'ab.pdf',
      // Nothing to read.
      'inline': null,
      'attachment': null,
      'attachment; size=42': null,
    };

    cases.forEach((header, expected) {
      test(header, () {
        expect(fileNameFromContentDisposition(header), expected);
      });
    });

    test('an absent header proposes nothing', () {
      expect(fileNameFromContentDisposition(null), isNull);
    });
  });
}
