import 'package:dio/dio.dart';

import '../cache/cache_interceptor.dart';
import '../errors/api_exception.dart';
import '../errors/parsing_exception.dart';
import '../errors/unexpected_content_type_exception.dart';
import 'api_client_config.dart';

/// A production-ready API client powered by Dio.
///
/// Use `ApiClientFactory` to create instances:
/// ```dart
/// final client = ApiClientFactory.create(baseUrl: 'https://api.example.com');
/// ```
///
/// Or with full configuration:
/// ```dart
/// final client = ApiClientFactory.create(
///   baseUrl: 'https://api.example.com',
///   connectTimeout: Duration(seconds: 60),
///   headers: {'Authorization': 'Bearer token'},
/// );
/// ```
class ApiClient {
  /// The underlying Dio instance.
  final Dio _dio;

  /// The configuration for this client.
  final ApiClientConfig config;

  /// Creates an [ApiClient] with the given [Dio] and [ApiClientConfig].
  ///
  /// Use `ApiClientFactory.create` or `ApiClientFactory.fromConfig` instead.
  ApiClient(this._dio, this.config);

  /// The base URL for all requests.
  String get baseUrl => config.baseUrl;

  /// The underlying Dio instance for advanced usage.
  ///
  /// Prefer using the ApiClient methods when possible.
  Dio get dio => _dio;

  /// The [CacheInterceptor] in this client's chain, or `null` when no cache is
  /// installed.
  ///
  /// This is how you reach the invalidation API — `clearCache()`,
  /// `invalidateUrl()`, `invalidatePath()` — on the instance the client is
  /// actually using:
  ///
  /// ```dart
  /// await client.cacheInterceptor?.clearCache();
  /// ```
  ///
  /// It was always reachable through `client.dio.interceptors.whereType<…>()`,
  /// which is not something anyone should have to discover. Not knowing it
  /// pushed consumers to build a `CacheInterceptor` by hand and pass it through
  /// `ApiClientConfig.interceptors` purely to keep a reference — see the note
  /// there for why that position costs a duplicate log line.
  ///
  /// Found by type rather than remembered at construction, so it works whether
  /// the cache came from `cacheConfig` or was wired in by hand.
  CacheInterceptor? get cacheInterceptor {
    for (final interceptor in _dio.interceptors) {
      if (interceptor is CacheInterceptor) return interceptor;
    }
    return null;
  }

  /// Closes the client and releases resources.
  void close({bool force = false}) {
    _dio.close(force: force);
  }

  /// Executes a Dio call and unwraps [DioException] into typed [ApiException].
  ///
  /// The `ErrorMapperInterceptor` maps Dio errors into [ApiException] subtypes
  /// but stores them in `DioException.error`. This helper extracts and rethrows
  /// the typed exception so callers can use `on ClientException catch` directly.
  Future<T> _execute<T>(Future<T> Function() dioCall) async {
    try {
      return await dioCall();
    } on DioException catch (e) {
      if (e.error is ApiException) throw e.error!;
      rethrow;
    }
  }

  /// Runs [decode] and converts any non-[ApiException] failure into a
  /// [ParsingException].
  ///
  /// This guards every typed-response method against `FormatException`,
  /// `TypeError`, and other errors thrown by the user-supplied `fromJson` or
  /// `parser` callbacks (or by internal cast/unwrap logic). [ApiException]
  /// instances thrown intentionally by the user (or by [_requireData] /
  /// [_extractData]) are rethrown unchanged.
  ///
  /// When [assertJson] is `true` and [ApiClientConfig.strictContentType] is
  /// enabled, the response's `Content-Type` header is verified to start with
  /// `application/json` before parsing — throws
  /// [UnexpectedContentTypeException] otherwise.
  T _parseOrThrow<T>(
    Response<dynamic> response,
    T Function() decode, {
    bool assertJson = false,
  }) {
    if (assertJson && config.strictContentType) {
      _assertJsonContentType(response);
    }
    try {
      return decode();
    } on ApiException {
      rethrow;
    } catch (e, st) {
      throw ParsingException(
        message: 'Failed to parse response body: $e',
        statusCode: response.statusCode,
        originalError: e,
        stackTrace: st,
      );
    }
  }

  /// Throws [UnexpectedContentTypeException] when the response's
  /// `Content-Type` header is missing or does not start with
  /// `application/json` (case-insensitive). Charset suffixes are tolerated.
  void _assertJsonContentType(Response<dynamic> response) {
    final raw = response.headers.value('content-type');
    if (raw == null ||
        !raw.toLowerCase().trimLeft().startsWith('application/json')) {
      throw UnexpectedContentTypeException(
        expectedContentType: 'application/json',
        actualContentType: raw,
        statusCode: response.statusCode,
      );
    }
  }

  // ========== HTTP Methods ==========

  /// Sends a GET request to [path].
  ///
  /// Example:
  /// ```dart
  /// final response = await client.get('/users');
  /// final response = await client.get('/users', queryParameters: {'page': 1});
  /// ```
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _execute(() => _dio.get<T>(
          path,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
        ));
  }

  /// Sends a POST request to [path].
  ///
  /// Example:
  /// ```dart
  /// final response = await client.post('/users', data: {'name': 'John'});
  /// ```
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _execute(() => _dio.post<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress,
        ));
  }

  /// Sends a PUT request to [path].
  ///
  /// Example:
  /// ```dart
  /// final response = await client.put('/users/1', data: {'name': 'Jane'});
  /// ```
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _execute(() => _dio.put<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress,
        ));
  }

  /// Sends a DELETE request to [path].
  ///
  /// Example:
  /// ```dart
  /// final response = await client.delete('/users/1');
  /// ```
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _execute(() => _dio.delete<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        ));
  }

  /// Sends a PATCH request to [path].
  ///
  /// Example:
  /// ```dart
  /// final response = await client.patch('/users/1', data: {'name': 'Updated'});
  /// ```
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _execute(() => _dio.patch<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress,
        ));
  }

  // ========== Typed Response Methods ==========
  //
  // Twelve shapes, five verbs, sixty methods — every one of them a signature
  // and a single call into [_typed]. They used to be sixty lines each of
  // identical request-then-parse plumbing, which is how GET and POST ended up
  // with twelve variants apiece while PUT and PATCH had two and DELETE none:
  // filling the gaps meant copying five hundred lines, so nobody did, and the
  // README claimed "all verbs" regardless.
  //
  // The twelve shapes answer three questions independently:
  //   * whole body, or the payload under `dataKey`?
  //   * one value (`Decode` = JSON object, `Parse` = anything)?
  //   * a list, and what does an absent payload mean — throw, null, or empty?

  /// Runs one typed request: send, then decode, with every failure of the
  /// decode step turned into a [ParsingException].
  ///
  /// [assertJson] enables the `Content-Type` check when
  /// [ApiClientConfig.strictContentType] is on; it is set for the `Decode`
  /// shapes, which genuinely require JSON, and left off for the `Parse` ones,
  /// which accept any payload by design.
  Future<R> _typed<R>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
    required R Function(Response<dynamic> response) decode,
    bool assertJson = false,
  }) async {
    final response = await _execute(
      () => _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        options: (options ?? Options()).copyWith(method: method),
      ),
    );
    return _parseOrThrow(response, () => decode(response),
        assertJson: assertJson);
  }

  // ---------- Shared payload readers ----------

  static R? _mapOrNull<R>(dynamic payload, R Function(dynamic) parse) =>
      payload == null ? null : parse(payload);

  /// Fails with a message that names the envelope, rather than a raw cast.
  ///
  /// The strict variants are supposed to refuse an absent payload — that is
  /// what separates them from `…OrNull` / `…OrEmpty`. What they were not
  /// supposed to do is refuse it with `type 'Null' is not a subtype of type
  /// 'Map<String, dynamic>'`, which names neither the key that was missing nor
  /// the envelope it was missing from.
  ///
  /// Reported by a consumer: a Jackson `default-property-inclusion:
  /// non_empty` on the server removes the `data` key from every empty
  /// collection, so the message a consumer meets first has to say which key
  /// and which variant would tolerate it.
  Never _missingPayload(String expected) {
    throw ApiException(
      message: 'Expected "${config.dataKey}" in the response envelope to be '
          '$expected, but it was absent or null. Use the OrNull or OrEmpty '
          'variant of this method if an empty payload is a valid answer here.',
    );
  }

  R _asObject<R>(dynamic payload, R Function(Map<String, dynamic>) from) {
    if (payload == null) _missingPayload('a JSON object');
    return from(payload as Map<String, dynamic>);
  }

  static R? _asObjectOrNull<R>(
          dynamic payload, R Function(Map<String, dynamic>) from) =>
      payload == null ? null : from(payload as Map<String, dynamic>);

  List<R> _asObjectList<R>(
      dynamic payload, R Function(Map<String, dynamic>) from) {
    if (payload == null) _missingPayload('a JSON array');
    return (payload as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(from)
        .toList();
  }

  List<R>? _asObjectListOrNull<R>(
          dynamic payload, R Function(Map<String, dynamic>) from) =>
      payload == null ? null : _asObjectList(payload, from);

  List<R> _asList<R>(dynamic payload, R Function(dynamic) parse) {
    if (payload == null) _missingPayload('a JSON array');
    return (payload as List<dynamic>).map(parse).toList();
  }

  List<R>? _asListOrNull<R>(dynamic payload, R Function(dynamic) parse) =>
      payload == null ? null : _asList(payload, parse);

  // ---------- GET ----------
  /// Parses the whole body with [parser].
  Future<T> getAndParse<T>(
    String path,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => parser(response.data),
    );
  }

  /// Deserialises the whole body as a JSON object.
  Future<T> getAndDecode<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) => fromJson(_requireData(response)),
    );
  }

  /// Parses `body[dataKey]` with [parser].
  Future<T> getAndParseData<T>(
    String path,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => parser(_extractData(response.data)),
    );
  }

  /// Parses `body[dataKey]`, or null when it is absent.
  Future<T?> getAndParseDataOrNull<T>(
    String path,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T?>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _mapOrNull(_extractData(response.data), parser),
    );
  }

  /// Deserialises `body[dataKey]` as a JSON object.
  Future<T> getAndDecodeData<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) => _asObject(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]`, or null when it is absent.
  Future<T?> getAndDecodeDataOrNull<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T?>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectOrNull(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list of JSON objects.
  Future<List<T>> getListAndDecodeData<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectList(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list, or null when it is absent.
  Future<List<T>?> getListAndDecodeDataOrNull<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>?>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectListOrNull(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list, empty when it is absent.
  Future<List<T>> getListAndDecodeDataOrEmpty<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectListOrNull(_extractData(response.data), fromJson) ?? <T>[],
    );
  }

  /// Parses `body[dataKey]` as a list with [parser].
  Future<List<T>> getListAndParseData<T>(
    String path,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _asList(_extractData(response.data), parser),
    );
  }

  /// Parses `body[dataKey]` as a list, or null when it is absent.
  Future<List<T>?> getListAndParseDataOrNull<T>(
    String path,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>?>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _asListOrNull(_extractData(response.data), parser),
    );
  }

  /// Parses `body[dataKey]` as a list, empty when it is absent.
  Future<List<T>> getListAndParseDataOrEmpty<T>(
    String path,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) =>
          _asListOrNull(_extractData(response.data), parser) ?? <T>[],
    );
  }

  // ---------- POST ----------
  /// Parses the whole body with [parser].
  Future<T> postAndParse<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => parser(response.data),
    );
  }

  /// Deserialises the whole body as a JSON object.
  Future<T> postAndDecode<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) => fromJson(_requireData(response)),
    );
  }

  /// Parses `body[dataKey]` with [parser].
  Future<T> postAndParseData<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => parser(_extractData(response.data)),
    );
  }

  /// Parses `body[dataKey]`, or null when it is absent.
  Future<T?> postAndParseDataOrNull<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T?>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _mapOrNull(_extractData(response.data), parser),
    );
  }

  /// Deserialises `body[dataKey]` as a JSON object.
  Future<T> postAndDecodeData<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) => _asObject(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]`, or null when it is absent.
  Future<T?> postAndDecodeDataOrNull<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T?>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectOrNull(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list of JSON objects.
  Future<List<T>> postListAndDecodeData<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectList(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list, or null when it is absent.
  Future<List<T>?> postListAndDecodeDataOrNull<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>?>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectListOrNull(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list, empty when it is absent.
  Future<List<T>> postListAndDecodeDataOrEmpty<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectListOrNull(_extractData(response.data), fromJson) ?? <T>[],
    );
  }

  /// Parses `body[dataKey]` as a list with [parser].
  Future<List<T>> postListAndParseData<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _asList(_extractData(response.data), parser),
    );
  }

  /// Parses `body[dataKey]` as a list, or null when it is absent.
  Future<List<T>?> postListAndParseDataOrNull<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>?>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _asListOrNull(_extractData(response.data), parser),
    );
  }

  /// Parses `body[dataKey]` as a list, empty when it is absent.
  Future<List<T>> postListAndParseDataOrEmpty<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) =>
          _asListOrNull(_extractData(response.data), parser) ?? <T>[],
    );
  }

  // ---------- PUT ----------
  /// Parses the whole body with [parser].
  Future<T> putAndParse<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => parser(response.data),
    );
  }

  /// Deserialises the whole body as a JSON object.
  Future<T> putAndDecode<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) => fromJson(_requireData(response)),
    );
  }

  /// Parses `body[dataKey]` with [parser].
  Future<T> putAndParseData<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => parser(_extractData(response.data)),
    );
  }

  /// Parses `body[dataKey]`, or null when it is absent.
  Future<T?> putAndParseDataOrNull<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T?>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _mapOrNull(_extractData(response.data), parser),
    );
  }

  /// Deserialises `body[dataKey]` as a JSON object.
  Future<T> putAndDecodeData<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) => _asObject(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]`, or null when it is absent.
  Future<T?> putAndDecodeDataOrNull<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T?>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectOrNull(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list of JSON objects.
  Future<List<T>> putListAndDecodeData<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectList(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list, or null when it is absent.
  Future<List<T>?> putListAndDecodeDataOrNull<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>?>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectListOrNull(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list, empty when it is absent.
  Future<List<T>> putListAndDecodeDataOrEmpty<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectListOrNull(_extractData(response.data), fromJson) ?? <T>[],
    );
  }

  /// Parses `body[dataKey]` as a list with [parser].
  Future<List<T>> putListAndParseData<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _asList(_extractData(response.data), parser),
    );
  }

  /// Parses `body[dataKey]` as a list, or null when it is absent.
  Future<List<T>?> putListAndParseDataOrNull<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>?>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _asListOrNull(_extractData(response.data), parser),
    );
  }

  /// Parses `body[dataKey]` as a list, empty when it is absent.
  Future<List<T>> putListAndParseDataOrEmpty<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) =>
          _asListOrNull(_extractData(response.data), parser) ?? <T>[],
    );
  }

  // ---------- PATCH ----------
  /// Parses the whole body with [parser].
  Future<T> patchAndParse<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => parser(response.data),
    );
  }

  /// Deserialises the whole body as a JSON object.
  Future<T> patchAndDecode<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) => fromJson(_requireData(response)),
    );
  }

  /// Parses `body[dataKey]` with [parser].
  Future<T> patchAndParseData<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => parser(_extractData(response.data)),
    );
  }

  /// Parses `body[dataKey]`, or null when it is absent.
  Future<T?> patchAndParseDataOrNull<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T?>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _mapOrNull(_extractData(response.data), parser),
    );
  }

  /// Deserialises `body[dataKey]` as a JSON object.
  Future<T> patchAndDecodeData<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) => _asObject(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]`, or null when it is absent.
  Future<T?> patchAndDecodeDataOrNull<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T?>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectOrNull(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list of JSON objects.
  Future<List<T>> patchListAndDecodeData<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectList(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list, or null when it is absent.
  Future<List<T>?> patchListAndDecodeDataOrNull<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>?>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectListOrNull(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list, empty when it is absent.
  Future<List<T>> patchListAndDecodeDataOrEmpty<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectListOrNull(_extractData(response.data), fromJson) ?? <T>[],
    );
  }

  /// Parses `body[dataKey]` as a list with [parser].
  Future<List<T>> patchListAndParseData<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _asList(_extractData(response.data), parser),
    );
  }

  /// Parses `body[dataKey]` as a list, or null when it is absent.
  Future<List<T>?> patchListAndParseDataOrNull<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>?>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _asListOrNull(_extractData(response.data), parser),
    );
  }

  /// Parses `body[dataKey]` as a list, empty when it is absent.
  Future<List<T>> patchListAndParseDataOrEmpty<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) =>
          _asListOrNull(_extractData(response.data), parser) ?? <T>[],
    );
  }

  // ---------- DELETE ----------
  /// Parses the whole body with [parser].
  Future<T> deleteAndParse<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => parser(response.data),
    );
  }

  /// Deserialises the whole body as a JSON object.
  Future<T> deleteAndDecode<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) => fromJson(_requireData(response)),
    );
  }

  /// Parses `body[dataKey]` with [parser].
  Future<T> deleteAndParseData<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => parser(_extractData(response.data)),
    );
  }

  /// Parses `body[dataKey]`, or null when it is absent.
  Future<T?> deleteAndParseDataOrNull<T>(
    String path,
    Object? data,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T?>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _mapOrNull(_extractData(response.data), parser),
    );
  }

  /// Deserialises `body[dataKey]` as a JSON object.
  Future<T> deleteAndDecodeData<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) => _asObject(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]`, or null when it is absent.
  Future<T?> deleteAndDecodeDataOrNull<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<T?>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectOrNull(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list of JSON objects.
  Future<List<T>> deleteListAndDecodeData<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectList(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list, or null when it is absent.
  Future<List<T>?> deleteListAndDecodeDataOrNull<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>?>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectListOrNull(_extractData(response.data), fromJson),
    );
  }

  /// Deserialises `body[dataKey]` as a list, empty when it is absent.
  Future<List<T>> deleteListAndDecodeDataOrEmpty<T>(
    String path,
    Object? data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: true,
      decode: (response) =>
          _asObjectListOrNull(_extractData(response.data), fromJson) ?? <T>[],
    );
  }

  /// Parses `body[dataKey]` as a list with [parser].
  Future<List<T>> deleteListAndParseData<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _asList(_extractData(response.data), parser),
    );
  }

  /// Parses `body[dataKey]` as a list, or null when it is absent.
  Future<List<T>?> deleteListAndParseDataOrNull<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>?>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) => _asListOrNull(_extractData(response.data), parser),
    );
  }

  /// Parses `body[dataKey]` as a list, empty when it is absent.
  Future<List<T>> deleteListAndParseDataOrEmpty<T>(
    String path,
    Object? data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _typed<List<T>>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      assertJson: false,
      decode: (response) =>
          _asListOrNull(_extractData(response.data), parser) ?? <T>[],
    );
  }

  /// Asserts that the response data is a non-null `Map<String, dynamic>`
  /// and returns it.
  ///
  /// Throws [ApiException] if the body is null (e.g. 204 No Content) or not
  /// a JSON object.
  Map<String, dynamic> _requireData(Response<dynamic> response) {
    final data = response.data;
    if (data == null) {
      throw ApiException(
        message: 'Expected JSON response body, got null '
            '(status ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    if (data is! Map<String, dynamic>) {
      throw ApiException(
        message: 'Expected JSON object, got ${data.runtimeType} '
            '(status ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  // ========== Data Extraction Methods (Envelope Unwrapping) ==========
  //
  // These methods extract `response.data[config.dataKey]` from envelope
  // responses like `{ "data": { ... } }`.

  /// Extracts the payload from an envelope response.
  ///
  /// The normal shape is a `Map` carrying [ApiClientConfig.dataKey], and that
  /// is what this returns.
  ///
  /// **A bare `List` or `null` at the root is accepted as the payload itself.**
  /// Backends routinely serialise an empty collection as `[]` rather than
  /// `{"data": []}` — the envelope is built by a serialiser that has nothing to
  /// wrap — and rejecting that made the `…OrEmpty` and `…OrNull` variants break
  /// on the commonest empty shape there is. They promise to tolerate "no data";
  /// refusing the way most servers spell it made the promise hollow, and the
  /// resulting crash arrived under HTTP 200, on the user who simply had nothing
  /// yet.
  ///
  /// Anything else — a `String`, a number — is still a shape nobody can guess
  /// at, and still throws.
  dynamic _extractData(dynamic responseData) {
    if (responseData == null) return null;
    if (responseData is List) return responseData;
    if (responseData is! Map<String, dynamic>) {
      throw ApiException(
        message: 'Expected envelope response (Map with '
            '"${config.dataKey}" key), got ${responseData.runtimeType}',
      );
    }
    return responseData[config.dataKey];
  }
}
