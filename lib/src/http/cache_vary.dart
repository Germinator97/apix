import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// Builds the fragment that scopes a cache or deduplication key to *who* is
/// asking, from the request headers named in [headerNames].
///
/// Returns `null` when there is nothing to scope on — no header names
/// configured, or none of them present on the request. A null fragment leaves
/// the key untouched, so an unauthenticated request keeps the plain key it
/// always had and still cannot collide with an authenticated one, which
/// carries a fragment.
///
/// ## Why this is hashed rather than embedded
///
/// Not to shorten the key. `EncryptedCacheStorage` encrypts bodies and headers
/// and **deliberately leaves keys in clear text** — the whole invalidation API
/// (`keys()`, `removeWhere()`, `removeByPrefix()`) is built on reading them.
/// Embedding an `Authorization` value would therefore write a live bearer
/// token to disk in clear, in the one storage explicitly chosen for sensitive
/// data. A digest scopes the key just as well and carries nothing back.
///
/// Truncated to 16 hex characters — 64 bits, far past what a per-install cache
/// namespace needs to stay collision-free, and short enough that a key still
/// reads at a glance while debugging.
///
/// ## Header lookup is case-insensitive
///
/// HTTP header names are case-insensitive and dio stores whatever the caller
/// wrote. `AuthConfig.headerName` is configurable too, so a consumer may well
/// be sending `authorization` or `X-Api-Key`. Matching on the exact spelling
/// would silently scope nothing — which looks exactly like working.
String? varyFingerprint(RequestOptions options, List<String> headerNames) {
  if (headerNames.isEmpty) return null;

  final wanted = headerNames.map((name) => name.toLowerCase()).toSet();
  final found = <String, String>{};

  options.headers.forEach((name, value) {
    final lower = name.toLowerCase();
    if (wanted.contains(lower)) {
      final rendered = _render(value);
      if (rendered.isNotEmpty) found[lower] = rendered;
    }
  });

  if (found.isEmpty) return null;

  // Sorted so two requests carrying the same headers in a different insertion
  // order share a fragment.
  final names = found.keys.toList()..sort();
  final material = names.map((name) => '$name=${found[name]}').join('&');

  return sha256.convert(utf8.encode(material)).toString().substring(0, 16);
}

/// Renders a header value, which dio allows to be a scalar or a list.
String _render(dynamic value) {
  if (value == null) return '';
  if (value is Iterable) return value.map((item) => '$item').join(',');
  return '$value';
}
