import 'dart:convert';

/// The file name a `Content-Disposition` header proposes, made safe to use
/// as one — or `null` when it proposes none that survives.
///
/// `filename*` (RFC 8187, `UTF-8''…` percent-encoded) wins over `filename`,
/// as RFC 6266 §4.3 prescribes. A `filename*` that does not decode — an
/// unknown charset, a malformed `%` escape, invalid UTF-8 — falls back to
/// `filename` instead of throwing: `Uri.decodeComponent`, the obvious tool,
/// throws on `%ZZ`.
///
/// A plain `filename` holding raw UTF-8 is common and not valid HTTP; through
/// `dart:io` each of its bytes arrives as one character, so `résumé.pdf`
/// reads `rÃ©sumÃ©.pdf` (measured). It is re-decoded when the characters form
/// valid UTF-8 and kept as received otherwise, which leaves a genuine
/// Latin-1 name untouched.
///
/// The name comes from the server, so it is sanitised (RFC 6266 §4.3): only
/// the last path segment is kept, whatever the separator; control and
/// bidirectional-override characters are removed; `.` and `..` are refused.
/// It can still be long, or collide with an existing file — deciding where
/// it goes remains the caller's job.
String? fileNameFromContentDisposition(String? header) {
  if (header == null) return null;
  final parameters = _parameters(header);

  final extended = parameters['filename*'];
  final fromExtended =
      extended == null ? null : _sanitise(_decodeExtendedValue(extended));
  if (fromExtended != null) return fromExtended;

  final plain = parameters['filename'];
  return plain == null ? null : _sanitise(_repairUtf8(plain));
}

/// The parameters after the disposition type, names lowercased, first
/// occurrence kept. Quoted values may hold `;` and backslash escapes.
Map<String, String> _parameters(String header) {
  final parameters = <String, String>{};
  var i = header.indexOf(';');
  if (i < 0) return parameters;
  i++;

  while (i < header.length) {
    while (i < header.length && ' \t;'.contains(header[i])) {
      i++;
    }
    final equals = header.indexOf('=', i);
    if (equals < 0) break;
    final semicolon = header.indexOf(';', i);
    if (semicolon >= 0 && semicolon < equals) {
      // A parameter with no value: skip it.
      i = semicolon + 1;
      continue;
    }

    final name = header.substring(i, equals).trim().toLowerCase();
    i = equals + 1;
    while (i < header.length && ' \t'.contains(header[i])) {
      i++;
    }

    final String value;
    if (i < header.length && header[i] == '"') {
      final quoted = StringBuffer();
      i++;
      while (i < header.length && header[i] != '"') {
        if (header[i] == r'\' && i + 1 < header.length) i++;
        quoted.write(header[i]);
        i++;
      }
      value = quoted.toString();
      final next = header.indexOf(';', i);
      i = next < 0 ? header.length : next + 1;
    } else {
      final next = header.indexOf(';', i);
      final end = next < 0 ? header.length : next;
      value = header.substring(i, end).trim();
      i = end + 1;
    }

    if (name.isNotEmpty) parameters.putIfAbsent(name, () => value);
  }
  return parameters;
}

/// Decodes an RFC 8187 `ext-value`: `charset'language'percent-encoded`.
String? _decodeExtendedValue(String value) {
  final unquoted =
      value.length >= 2 && value.startsWith('"') && value.endsWith('"')
          ? value.substring(1, value.length - 1)
          : value;
  final first = unquoted.indexOf("'");
  if (first < 0) return null;
  final second = unquoted.indexOf("'", first + 1);
  if (second < 0) return null;

  final bytes = _percentDecode(unquoted.substring(second + 1));
  if (bytes == null) return null;
  switch (unquoted.substring(0, first).trim().toLowerCase()) {
    case 'utf-8':
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return null;
      }
    case 'iso-8859-1':
      return latin1.decode(bytes);
    default:
      return null;
  }
}

List<int>? _percentDecode(String encoded) {
  final bytes = <int>[];
  for (var i = 0; i < encoded.length; i++) {
    final unit = encoded.codeUnitAt(i);
    if (unit == 0x25) {
      if (i + 2 >= encoded.length) return null;
      final high = _hexDigit(encoded.codeUnitAt(i + 1));
      final low = _hexDigit(encoded.codeUnitAt(i + 2));
      if (high == null || low == null) return null;
      bytes.add(high * 16 + low);
      i += 2;
    } else if (unit > 0x7F) {
      return null;
    } else {
      bytes.add(unit);
    }
  }
  return bytes;
}

int? _hexDigit(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  if (unit >= 0x41 && unit <= 0x46) return unit - 0x41 + 10;
  if (unit >= 0x61 && unit <= 0x66) return unit - 0x61 + 10;
  return null;
}

/// Re-decodes a value whose characters are really UTF-8 bytes.
String _repairUtf8(String value) {
  final units = value.codeUnits;
  if (units.every((u) => u < 0x80) || units.any((u) => u > 0xFF)) {
    return value;
  }
  try {
    return utf8.decode(latin1.encode(value));
  } on FormatException {
    return value;
  }
}

final RegExp _pathSeparator = RegExp(r'[/\\]');
final RegExp _unsafeCharacters =
    RegExp('[\u0000-\u001F\u007F\u202A-\u202E\u2066-\u2069]');

String? _sanitise(String? name) {
  if (name == null) return null;
  final segment = name.split(_pathSeparator).last;
  final cleaned = segment.replaceAll(_unsafeCharacters, '').trim();
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return null;
  return cleaned;
}
