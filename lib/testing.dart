/// Test-only entry point for apix consumers.
///
/// Everything needed to exercise network behaviour **without I/O**: stub an
/// adapter, hand back a scripted body, assert what the client did with it.
///
/// These types are deliberately not in `package:apix/apix.dart` — they have no
/// business in production autocomplete. Import them only from `test/`:
///
/// ```dart
/// import 'package:apix/apix.dart';
/// import 'package:apix/testing.dart';
///
/// class FakeAdapter implements HttpClientAdapter {
///   @override
///   Future<ResponseBody> fetch(
///     RequestOptions options,
///     Stream<List<int>>? requestStream,
///     Future<dynamic>? cancelFuture,
///   ) async {
///     return ResponseBody.fromString(
///       '{"code":"RATE_LIMITED","message":"Slow down"}',
///       429,
///       headers: {
///         Headers.contentTypeHeader: ['application/json'],
///         'retry-after': ['30'],
///       },
///     );
///   }
///
///   @override
///   void close({bool force = false}) {}
/// }
///
/// final client = ApiClientFactory.create(
///   baseUrl: 'https://api.test',
///   httpClientAdapter: FakeAdapter(),
/// );
/// ```
///
/// Without this entry point every consumer's network test had to
/// `import 'package:dio/dio.dart'` directly, which made apix's declared dio
/// version range a constraint on their test suite too — the one place a range
/// mismatch is most likely to surface first.
library;

export 'package:dio/dio.dart'
    show
        BaseOptions,
        Dio,
        Headers,
        HttpClientAdapter,
        RequestOptions,
        ResponseBody,
        ResponseType;
