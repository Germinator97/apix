import 'package:dio/dio.dart';

/// Whether [contentType] names a JSON media type, by dio's own rule.
///
/// `application/json`, `text/json` and any `*+json` subtype
/// (`application/problem+json`), parameters ignored. Reusing dio's rule is
/// the point: apix decodes a body received as bytes or text exactly when dio
/// would have decoded it under `ResponseType.json` — never more, never less.
///
/// A malformed value is not JSON. That is what recent dio versions answer;
/// dio 5.4.0, the declared floor, lets `MediaType.parse` throw instead, so
/// the throw is turned into the same answer here rather than escaping the
/// interceptor that asked.
bool isJsonContentType(String? contentType) {
  if (contentType == null) return false;
  try {
    return Transformer.isJsonMimeType(contentType);
  } on FormatException {
    return false;
  }
}
