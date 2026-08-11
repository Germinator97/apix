/// Renders [uri] with its query **values** replaced, keeping the names.
///
/// `https://api.test/reset?token=abc&lang=fr` becomes
/// `https://api.test/reset?token=[REDACTED]&lang=[REDACTED]`.
///
/// ## Why the names stay
///
/// Removing the query outright would be the safe-looking choice and a worse
/// one: knowing *which* parameters a failing request carried is most of the
/// value of having the URL at all, and a report that cannot distinguish
/// `?page=` from `?token=` sends the reader back to the code. Names are
/// written by the API, values by the caller — it is the values that carry the
/// session token, the national id, the search term someone typed.
///
/// ## Why the path is left alone
///
/// A path can identify too (`/members/1234/balance`), and redacting it would
/// collapse every endpoint into one unreadable string — destroying the
/// grouping that makes a tracker useful. Where a path segment is sensitive,
/// that is a decision about your API's shape, not something this function can
/// take back. `EncryptedCacheStorage` documents the same boundary for the same
/// reason.
/// The result is assembled as text rather than through `Uri.replace`, which
/// percent-encodes the placeholder into `%5BREDACTED%5D` — correct as a URI and
/// unreadable as a report, which is the only thing this string is ever used as.
String redactQueryValues(Uri uri, {String placeholder = '[REDACTED]'}) {
  if (uri.query.isEmpty) return uri.toString();

  final names = uri.queryParametersAll.keys.toList()..sort();
  final redacted = names.map((name) => '$name=$placeholder').join('&');

  final buffer = StringBuffer();
  if (uri.hasScheme) buffer.write('${uri.scheme}://');
  buffer
    ..write(uri.authority)
    ..write(uri.path)
    ..write('?$redacted');
  if (uri.hasFragment) buffer.write('#${uri.fragment}');

  return buffer.toString();
}
