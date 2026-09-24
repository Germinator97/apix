import 'dart:typed_data';

/// Renders a request or response body for a log line or a tracker field: at
/// most [maxLength] characters, then `... [truncated]`.
///
/// It never builds more text than it keeps. Rendering used to call
/// `body.toString()` first and cut afterwards: for a 5 MB PDF received as a
/// `Uint8List`, that built a 24-million-character string on the calling
/// isolate — measured at about 170 ms per log line on a desktop — to print
/// the thousand characters `[37, 80, 68, 70, …` of it.
///
/// - A `Uint8List` renders as `<binary: N bytes>`, without being read — at
///   any depth. It is the one type dio sends and receives as raw bytes; any
///   other `List<int>` is sent as JSON, so `[1, 2, 3]` stays a list.
/// - A `Map`, `List` or `Set` renders exactly as its `toString()` would —
///   same separators, same `[...]` for a cycle — but stops as soon as the
///   limit is passed, so a decoded JSON response costs what its preview
///   keeps, not what it weighs.
/// - A `String` is cut without being copied first.
/// - Anything else goes through its own `toString()`, which apix cannot
///   bound.
///
/// A negative [maxLength] is read as `0` rather than throwing out of a log
/// call.
String previewBody(Object? body, int maxLength) {
  final limit = maxLength < 0 ? 0 : maxLength;
  if (body is String) return _clip(body, limit);
  if (body is Uint8List || body is Map || body is Iterable) {
    final writer = _BoundedWriter(limit);
    try {
      writer.value(body);
    } on _LimitReached {
      return '${writer.text.substring(0, limit)}... [truncated]';
    }
    return writer.text;
  }
  return _clip('$body', limit);
}

String _clip(String text, int limit) =>
    text.length <= limit ? text : '${text.substring(0, limit)}... [truncated]';

/// Thrown by [_BoundedWriter] once it holds one character past its limit —
/// the proof that the full rendering would not fit.
class _LimitReached implements Exception {
  const _LimitReached();
}

class _BoundedWriter {
  _BoundedWriter(this._limit);

  final int _limit;
  final StringBuffer _buffer = StringBuffer();

  /// Containers being rendered, by identity, to render a cycle the way
  /// `toString()` does rather than forever.
  final List<Object> _open = [];

  String get text => _buffer.toString();

  void _write(String part) {
    final room = _limit + 1 - _buffer.length;
    if (part.length < room) {
      _buffer.write(part);
      return;
    }
    _buffer.write(part.substring(0, room));
    throw const _LimitReached();
  }

  void value(Object? value) {
    if (value is Uint8List) {
      _write('<binary: ${value.length} bytes>');
    } else if (value is Map) {
      _container(value, '{', '}', () {
        var first = true;
        for (final entry in value.entries) {
          if (!first) _write(', ');
          first = false;
          this.value(entry.key);
          _write(': ');
          this.value(entry.value);
        }
      });
    } else if (value is List) {
      _elements(value, '[', ']');
    } else if (value is Set) {
      _elements(value, '{', '}');
    } else if (value is String) {
      _write(value);
    } else {
      // Includes the lazy iterables, whose own `toString()` is already
      // abbreviated by the SDK.
      _write('$value');
    }
  }

  void _elements(Iterable<Object?> elements, String open, String close) {
    _container(elements, open, close, () {
      var first = true;
      for (final element in elements) {
        if (!first) _write(', ');
        first = false;
        value(element);
      }
    });
  }

  void _container(
    Object container,
    String open,
    String close,
    void Function() writeContents,
  ) {
    if (_open.any((c) => identical(c, container))) {
      _write('$open...$close');
      return;
    }
    _open.add(container);
    try {
      _write(open);
      writeContents();
      _write(close);
    } finally {
      _open.removeLast();
    }
  }
}
