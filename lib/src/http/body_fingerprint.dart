import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Condenses a request body into the fragment that distinguishes two otherwise
/// identical requests.
///
/// Returns `null` when there is no body, which leaves the key exactly as it was
/// before this existed — so a `GET` keeps the key it has always had and no
/// stored entry is orphaned by adding this.
///
/// ## Why this is shared rather than written twice
///
/// It was written twice, and the two copies disagreed.
///
/// `RequestDeduplicator.generateKey` hashed the body from the start.
/// `CacheInterceptor._generateCacheKey` never did — so `cacheableMethods`,
/// a public list documented without reservation, could be widened to `POST`
/// and two searches with different payloads would share one entry. Measured:
/// `{"q":"alice"}` and `{"q":"bob"}` collapsed to a single network call, and
/// the second caller was served the first one's results.
///
/// That is the third occurrence of one shape: the same package building the
/// same key in two places and getting different answers. Keeping one
/// implementation is the only version of the fix that stays fixed.
///
/// ## Why a digest rather than the value
///
/// Same reason as `varyFingerprint`: `EncryptedCacheStorage` encrypts bodies
/// and **deliberately leaves keys in clear text**, because the whole
/// invalidation API reads them. Embedding a request body would therefore write
/// the payload — a password, an account number — beside the entry, in the one
/// storage chosen for sensitive data.
///
/// Truncated to 16 hex characters, matching `varyFingerprint`: 64 bits is far
/// past what a per-install namespace needs, and a key still reads at a glance
/// while debugging.
String? bodyFingerprint(dynamic data) {
  if (data == null) return null;

  final String material;
  if (data is String) {
    material = data;
  } else if (data is Map || data is List) {
    // `jsonEncode` can refuse a body holding something it cannot represent —
    // a `FormData`, a stream, a consumer's own object. Falling back to
    // `toString` keeps a body-bearing request keyed on *something* rather than
    // on nothing at all, which is the outcome this function exists to prevent.
    try {
      material = jsonEncode(data);
    } catch (_) {
      return _digest(data.toString());
    }
  } else {
    material = data.toString();
  }

  return _digest(material);
}

String _digest(String material) =>
    sha256.convert(utf8.encode(material)).toString().substring(0, 16);
