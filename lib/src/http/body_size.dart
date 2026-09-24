import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'header_values.dart';

/// Key under which `StatusPreservingTransformer` records how many bytes of a
/// JSON or text body it received.
///
/// It sees every byte of those bodies anyway; a decoded `Map` no longer can
/// say how large it was, and a server that streams its JSON sends no
/// `Content-Length` to fall back on.
const String receivedBodyBytesKey = '_apix_received_body_bytes';

/// Size in bytes of the body [options] sends, or `null` when it cannot be
/// told without encoding it.
///
/// Read after dio has sent the request, `Content-Length` is exact: dio
/// writes it whenever it encodes a body — a map, a list, a string, form
/// data. Before that (still in flight, or a failure raised before sending),
/// only what is sized without encoding is measured: raw bytes, text, form
/// data.
///
/// Never a rendering of the body. This used to be `data.toString().length`:
/// for a 5 MB upload, a 24-million-character string, and a count of
/// characters of Dart's `{key: value}` rendering rather than of bytes.
int? requestBodySize(RequestOptions options) {
  final declared =
      _declaredLength(options.headers[Headers.contentLengthHeader]);
  if (declared != null) return declared;
  final data = options.data;
  if (data is Uint8List) return data.length;
  if (data is String) return utf8ByteLength(data);
  if (data is FormData) return data.length;
  return null;
}

/// Size in bytes of the body [response] carried, as received — after any
/// transport decompression — or `null` when it cannot be told.
///
/// Measured on raw bytes; recorded by apix's transformer for JSON and text;
/// otherwise read from `Content-Length` when the body was not
/// content-encoded (a compressed length is not the size of what was
/// received). A stream is not measured.
int? responseBodySize(Response<dynamic> response) {
  final data = response.data;
  if (data is List<int>) return data.length;

  final recorded = response.requestOptions.extra[receivedBodyBytesKey];
  if (recorded is int) return recorded;

  if (data is String) return utf8ByteLength(data);

  final encoding = firstHeaderValue(response.headers, 'content-encoding');
  if (encoding != null && encoding.trim().toLowerCase() != 'identity') {
    return null;
  }
  return _declaredLength(
      firstHeaderValue(response.headers, Headers.contentLengthHeader));
}

int? _declaredLength(Object? value) {
  if (value == null) return null;
  final length = int.tryParse('$value'.trim());
  return length != null && length >= 0 ? length : null;
}

/// Number of bytes [text] takes in UTF-8, counted without encoding it.
///
/// A lone surrogate counts 3, as `utf8.encode` writes it: U+FFFD.
int utf8ByteLength(String text) {
  var bytes = 0;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit < 0x80) {
      bytes += 1;
    } else if (unit < 0x800) {
      bytes += 2;
    } else if (unit >= 0xD800 &&
        unit <= 0xDBFF &&
        i + 1 < text.length &&
        (text.codeUnitAt(i + 1) & 0xFC00) == 0xDC00) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}
