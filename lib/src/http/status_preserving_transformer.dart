import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../errors/parsing_exception.dart';
import 'header_values.dart';
import 'json_media_type.dart';

/// Wraps dio's transformer so that a body which fails to decode never costs
/// the response its status.
///
/// dio decodes a JSON body **before** any interceptor runs, and when the
/// decoding throws, `assureDioException` builds an exception with no
/// `response` at all: the status, the headers and the body are gone before
/// apix sees anything. Measured on both dio bounds, under the default
/// `ResponseType.json`:
///
/// - a `400` with a truncated JSON body reached the caller as
///   `ApiException('Unknown error')`, status null;
/// - a `401` whose body was `Unauthorized` in plain text under
///   `Content-Type: application/json` did the same — no
///   `UnauthorizedException`, and no token refresh, since the auth
///   interceptor reads a status that no longer exists;
/// - a `200` with a truncated body gave that same `Unknown error` instead of
///   the `ParsingException` whose documentation cites "truncated JSON" as its
///   example.
///
/// No interceptor can hand back a status dio never attached, so the repair
/// lives here. On a decoding failure:
///
/// - a response dio treats as an error keeps its status, its headers and its
///   body as text, so the error chain maps it like any other failure;
/// - a response dio treats as a success becomes a `ParsingException` that
///   carries the status — for the raw verbs as well as the typed shapes, and
///   before the cache, the metrics or the validator could take it for a
///   success.
///
/// A malformed `Content-Type` is not JSON: recent dio versions read such a
/// body as text, and the 5.4.0 floor, whose media-type parser throws, now
/// does too.
///
/// The body is **recorded as it streams**, never gathered up front: at the
/// floor it is dio's transformer that reports receive progress while it
/// reads, and draining the stream first would reduce that to one final
/// event. Bytes and streams are passed through untouched — they cannot fail
/// to decode.
class StatusPreservingTransformer extends Transformer {
  /// Wraps [inner], which does all the decoding.
  StatusPreservingTransformer(this.inner);

  /// The transformer that decodes; this one only keeps what it drops.
  final Transformer inner;

  @override
  Future<String> transformRequest(RequestOptions options) =>
      inner.transformRequest(options);

  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody responseBody,
  ) async {
    final type = options.responseType;
    if (type != ResponseType.json && type != ResponseType.plain) {
      return inner.transformResponse(options, responseBody);
    }

    final recording = _Recording(responseBody.stream);
    responseBody.stream = recording.stream;
    try {
      return await inner.transformResponse(options, responseBody);
    } on FormatException catch (error, stackTrace) {
      final text = utf8.decode(await recording.all(), allowMalformed: true);
      final headers = Headers.fromMap(responseBody.headers);
      final claimsJson = type == ResponseType.json &&
          isJsonContentType(firstHeaderValue(headers, 'content-type'));
      if (!claimsJson || !options.validateStatus(responseBody.statusCode)) {
        return text;
      }
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: responseBody.statusCode,
          statusMessage: responseBody.statusMessage,
          headers: headers,
          data: text,
        ),
        error: ParsingException(
          message: 'Failed to parse response body: $error',
          statusCode: responseBody.statusCode,
          originalError: error,
          stackTrace: stackTrace,
        ),
        stackTrace: stackTrace,
        message: 'The response body is not valid JSON.',
      );
    }
  }
}

/// Forwards a response stream to its consumer while keeping every chunk, so
/// a body that failed to decode can still be handed back whole.
///
/// When the consumer gives up half-way — a streaming JSON decoder cancels on
/// its first error — the recording keeps reading to the end. A transport
/// failure outranks the decoding one and is rethrown by [all].
class _Recording {
  _Recording(this._source) {
    _controller = StreamController<Uint8List>(
      sync: true,
      onListen: _start,
      onPause: () => _subscription?.pause(),
      onResume: () => _subscription?.resume(),
      onCancel: () {
        _consumerGone = true;
        _subscription?.resume();
      },
    );
  }

  final Stream<Uint8List> _source;
  late final StreamController<Uint8List> _controller;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  final Completer<void> _done = Completer<void>();
  StreamSubscription<Uint8List>? _subscription;
  bool _consumerGone = false;
  Object? _error;
  StackTrace? _errorStackTrace;

  Stream<Uint8List> get stream => _controller.stream;

  void _start() {
    _subscription ??= _source.listen(
      (chunk) {
        _bytes.add(chunk);
        if (!_consumerGone) _controller.add(chunk);
      },
      // An error ends the source too — `cancelOnError` means no `onDone`
      // follows — so it completes the recording, or [all] would wait forever.
      onError: (Object error, StackTrace stackTrace) {
        _error ??= error;
        _errorStackTrace ??= stackTrace;
        if (!_consumerGone) _controller.addError(error, stackTrace);
        _finish();
      },
      onDone: _finish,
      cancelOnError: true,
    );
  }

  void _finish() {
    if (!_done.isCompleted) _done.complete();
    if (!_consumerGone) _controller.close();
  }

  /// Every byte of the body, once the source has ended.
  Future<Uint8List> all() async {
    _consumerGone = true;
    _start();
    _subscription!.resume();
    await _done.future;
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _errorStackTrace!);
    return _bytes.takeBytes();
  }
}
