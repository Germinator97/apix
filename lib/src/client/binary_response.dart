import 'dart:typed_data';

import '../http/content_disposition.dart';

/// A response whose body is binary — a PDF, an image, an archive — with the
/// status and headers that come with it.
///
/// Returned by the `…AndReadBytes` methods of `ApiClient`. It carries no dio
/// type, so the data layer that downloads a file does not depend on dio.
///
/// ```dart
/// final pdf = await client.getAndReadBytes(
///   '/reports/2026-08',
///   expectedContentTypes: ['application/pdf'],
/// );
/// if (pdf.isEmpty) return; // 204, or an empty body
/// await File('${dir.path}/${pdf.fileName ?? 'report.pdf'}')
///     .writeAsBytes(pdf.bytes);
/// ```
class BinaryResponse {
  /// Creates a [BinaryResponse].
  ///
  /// Header names are lowercased, and values of names that differ only by
  /// case are merged. Useful to build one in a test.
  BinaryResponse({
    required this.bytes,
    required this.statusCode,
    Map<String, List<String>> headers = const {},
  }) : headers = _normalise(headers);

  /// The body, byte for byte as received. Empty for a `204` or an empty body.
  final Uint8List bytes;

  /// The HTTP status of the response.
  final int statusCode;

  /// Every response header, names lowercased, values in the order received.
  final Map<String, List<String>> headers;

  /// The value of the header [name], case-insensitively, or `null`.
  ///
  /// A header sent more than once comes back as its values joined by `", "`
  /// — the same form a cache hit restores, so a live response and a cached
  /// one read alike.
  String? header(String name) {
    final values = headers[name.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    return values.join(', ');
  }

  /// The `Content-Type` of the body, parameters included, or `null`.
  String? get contentType => _first('content-type');

  /// The file name the server proposes in `Content-Disposition`, or `null`.
  ///
  /// `filename*` (RFC 8187) wins over `filename`. The name is sanitised —
  /// last path segment only, no control or bidirectional-override
  /// characters, never `.` or `..` — since it comes from the server and is
  /// about to become a path. Where the file goes is still yours to decide.
  String? get fileName =>
      fileNameFromContentDisposition(_first('content-disposition'));

  /// Whether the body is empty — a `204 No Content`, or a `200` without body.
  bool get isEmpty => bytes.isEmpty;

  String? _first(String name) {
    final values = headers[name];
    return values == null || values.isEmpty ? null : values.first;
  }

  static Map<String, List<String>> _normalise(
    Map<String, List<String>> headers,
  ) {
    final merged = <String, List<String>>{};
    headers.forEach((name, values) {
      (merged[name.toLowerCase()] ??= []).addAll(values);
    });
    return Map.unmodifiable({
      for (final entry in merged.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
  }

  @override
  String toString() => 'BinaryResponse($statusCode, '
      '${contentType ?? 'no content type'}, ${bytes.length} bytes)';
}
