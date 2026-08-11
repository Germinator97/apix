import 'package:dio/dio.dart';

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

  /// Sends a GET request and parses the response using [parser].
  ///
  /// Formats `response.data` directly. Use for any response type.
  ///
  /// Example:
  /// ```dart
  /// final count = await client.getAndParse('/users/count', (data) => data as int);
  /// ```
  Future<T> getAndParse<T>(
    String path,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(response, () => parser(response.data));
  }

  /// Sends a GET request and deserializes a JSON object response.
  ///
  /// Formats `response.data` as `Map<String, dynamic>`.
  ///
  /// Example:
  /// ```dart
  /// final user = await client.getAndDecode('/users/1', User.fromJson);
  /// ```
  Future<T> getAndDecode<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => fromJson(_requireData(response)),
      assertJson: true,
    );
  }

  /// Sends a POST request and parses the response using [parser].
  ///
  /// Formats `response.data` directly.
  Future<T> postAndParse<T>(
    String path,
    dynamic data,
    T Function(dynamic responseData) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(response, () => parser(response.data));
  }

  /// Sends a POST request and deserializes the response.
  ///
  /// Formats `response.data` as `Map<String, dynamic>`.
  ///
  /// Example:
  /// ```dart
  /// final user = await client.postAndDecode(
  ///   '/users',
  ///   {'name': 'John'},
  ///   User.fromJson,
  /// );
  /// ```
  Future<T> postAndDecode<T>(
    String path,
    dynamic data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => fromJson(_requireData(response)),
      assertJson: true,
    );
  }

  /// Sends a PUT request and parses the response using [parser].
  ///
  /// Formats `response.data` directly.
  Future<T> putAndParse<T>(
    String path,
    dynamic data,
    T Function(dynamic responseData) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await put<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(response, () => parser(response.data));
  }

  /// Sends a PUT request and deserializes the response.
  ///
  /// Formats `response.data` as `Map<String, dynamic>`.
  Future<T> putAndDecode<T>(
    String path,
    dynamic data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await put<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => fromJson(_requireData(response)),
      assertJson: true,
    );
  }

  /// Sends a PATCH request and parses the response using [parser].
  ///
  /// Formats `response.data` directly.
  Future<T> patchAndParse<T>(
    String path,
    dynamic data,
    T Function(dynamic responseData) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await patch<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(response, () => parser(response.data));
  }

  /// Sends a PATCH request and deserializes the response.
  ///
  /// Formats `response.data` as `Map<String, dynamic>`.
  Future<T> patchAndDecode<T>(
    String path,
    dynamic data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await patch<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => fromJson(_requireData(response)),
      assertJson: true,
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

  // ---------- GET Data ----------

  /// Sends a GET request and parses `response.data[dataKey]` using [parser].
  ///
  /// Example:
  /// ```dart
  /// // Response: { "data": "2024-01-01T00:00:00Z" }
  /// final date = await client.getAndParseData(
  ///   '/server/time',
  ///   (data) => DateTime.parse(data as String),
  /// );
  /// ```
  Future<T> getAndParseData<T>(
    String path,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => parser(_extractData(response.data)),
    );
  }

  /// Sends a GET request and parses `response.data[dataKey]`, returning null
  /// if the extracted data is null.
  ///
  /// Example:
  /// ```dart
  /// // Response: { "data": null }
  /// final date = await client.getAndParseDataOrNull('/server/time', ...);
  /// // returns null
  /// ```
  Future<T?> getAndParseDataOrNull<T>(
    String path,
    T Function(dynamic data) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(response, () {
      final data = _extractData(response.data);
      return data == null ? null : parser(data);
    });
  }

  /// Sends a GET request and deserializes `response.data[dataKey]` as a JSON object.
  ///
  /// Example:
  /// ```dart
  /// // Response: { "data": { "id": 1, "name": "John" } }
  /// final user = await client.getAndDecodeData('/users/1', User.fromJson);
  /// ```
  Future<T> getAndDecodeData<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => fromJson(_extractData(response.data) as Map<String, dynamic>),
      assertJson: true,
    );
  }

  /// Sends a GET request and deserializes `response.data[dataKey]`, returning
  /// null if the extracted data is null.
  Future<T?> getAndDecodeDataOrNull<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () {
        final data = _extractData(response.data);
        if (data == null) return null;
        return fromJson(data as Map<String, dynamic>);
      },
      assertJson: true,
    );
  }

  /// Sends a GET request and deserializes `response.data[dataKey]` as a list
  /// of JSON objects.
  ///
  /// Example:
  /// ```dart
  /// // Response: { "data": [{ "id": 1 }, { "id": 2 }] }
  /// final users = await client.getListAndDecodeData('/users', User.fromJson);
  /// ```
  Future<List<T>> getListAndDecodeData<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => (_extractData(response.data) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((json) => fromJson(json))
          .toList(),
      assertJson: true,
    );
  }

  /// Sends a GET request and deserializes `response.data[dataKey]` as a list,
  /// returning null if the extracted data is null.
  Future<List<T>?> getListAndDecodeDataOrNull<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () {
        final data = _extractData(response.data);
        if (data == null) return null;
        return (data as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((json) => fromJson(json))
            .toList();
      },
      assertJson: true,
    );
  }

  /// Sends a GET request and deserializes `response.data[dataKey]` as a list,
  /// returning an empty list if the extracted data is null.
  Future<List<T>> getListAndDecodeDataOrEmpty<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () {
        final data = _extractData(response.data);
        if (data == null) return <T>[];
        return (data as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((json) => fromJson(json))
            .toList();
      },
      assertJson: true,
    );
  }

  /// Sends a GET request and parses `response.data[dataKey]` as a list
  /// using [parser].
  ///
  /// Example:
  /// ```dart
  /// // Response: { "data": ["admin", "editor"] }
  /// final roles = await client.getListAndParseData(
  ///   '/roles',
  ///   (item) => item as String,
  /// );
  /// ```
  Future<List<T>> getListAndParseData<T>(
    String path,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => (_extractData(response.data) as List<dynamic>)
          .map((item) => parser(item))
          .toList(),
    );
  }

  /// Sends a GET request and parses `response.data[dataKey]` as a list,
  /// returning null if the extracted data is null.
  Future<List<T>?> getListAndParseDataOrNull<T>(
    String path,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(response, () {
      final data = _extractData(response.data);
      if (data == null) return null;
      return (data as List<dynamic>).map((item) => parser(item)).toList();
    });
  }

  /// Sends a GET request and parses `response.data[dataKey]` as a list,
  /// returning an empty list if the extracted data is null.
  Future<List<T>> getListAndParseDataOrEmpty<T>(
    String path,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(response, () {
      final data = _extractData(response.data);
      if (data == null) return <T>[];
      return (data as List<dynamic>).map((item) => parser(item)).toList();
    });
  }

  // ---------- POST Data ----------

  /// Sends a POST request and parses `response.data[dataKey]` using [parser].
  Future<T> postAndParseData<T>(
    String path,
    dynamic data,
    T Function(dynamic responseData) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => parser(_extractData(response.data)),
    );
  }

  /// Sends a POST request and parses `response.data[dataKey]`, returning null
  /// if the extracted data is null.
  Future<T?> postAndParseDataOrNull<T>(
    String path,
    dynamic data,
    T Function(dynamic responseData) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(response, () {
      final extracted = _extractData(response.data);
      return extracted == null ? null : parser(extracted);
    });
  }

  /// Sends a POST request and deserializes `response.data[dataKey]` as a
  /// JSON object.
  ///
  /// Example:
  /// ```dart
  /// // Response: { "data": { "id": 1, "name": "John" } }
  /// final user = await client.postAndDecodeData(
  ///   '/users',
  ///   {'name': 'John'},
  ///   User.fromJson,
  /// );
  /// ```
  Future<T> postAndDecodeData<T>(
    String path,
    dynamic data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => fromJson(_extractData(response.data) as Map<String, dynamic>),
      assertJson: true,
    );
  }

  /// Sends a POST request and deserializes `response.data[dataKey]`, returning
  /// null if the extracted data is null.
  Future<T?> postAndDecodeDataOrNull<T>(
    String path,
    dynamic data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () {
        final extracted = _extractData(response.data);
        if (extracted == null) return null;
        return fromJson(extracted as Map<String, dynamic>);
      },
      assertJson: true,
    );
  }

  /// Sends a POST request and deserializes `response.data[dataKey]` as a list
  /// of JSON objects.
  Future<List<T>> postListAndDecodeData<T>(
    String path,
    dynamic data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => (_extractData(response.data) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((json) => fromJson(json))
          .toList(),
      assertJson: true,
    );
  }

  /// Sends a POST request and deserializes `response.data[dataKey]` as a list,
  /// returning null if the extracted data is null.
  Future<List<T>?> postListAndDecodeDataOrNull<T>(
    String path,
    dynamic data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () {
        final extracted = _extractData(response.data);
        if (extracted == null) return null;
        return (extracted as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((json) => fromJson(json))
            .toList();
      },
      assertJson: true,
    );
  }

  /// Sends a POST request and deserializes `response.data[dataKey]` as a list,
  /// returning an empty list if the extracted data is null.
  Future<List<T>> postListAndDecodeDataOrEmpty<T>(
    String path,
    dynamic data,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () {
        final extracted = _extractData(response.data);
        if (extracted == null) return <T>[];
        return (extracted as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((json) => fromJson(json))
            .toList();
      },
      assertJson: true,
    );
  }

  /// Sends a POST request and parses `response.data[dataKey]` as a list
  /// using [parser].
  Future<List<T>> postListAndParseData<T>(
    String path,
    dynamic data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(
      response,
      () => (_extractData(response.data) as List<dynamic>)
          .map((item) => parser(item))
          .toList(),
    );
  }

  /// Sends a POST request and parses `response.data[dataKey]` as a list,
  /// returning null if the extracted data is null.
  Future<List<T>?> postListAndParseDataOrNull<T>(
    String path,
    dynamic data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(response, () {
      final extracted = _extractData(response.data);
      if (extracted == null) return null;
      return (extracted as List<dynamic>).map((item) => parser(item)).toList();
    });
  }

  /// Sends a POST request and parses `response.data[dataKey]` as a list,
  /// returning an empty list if the extracted data is null.
  Future<List<T>> postListAndParseDataOrEmpty<T>(
    String path,
    dynamic data,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return _parseOrThrow(response, () {
      final extracted = _extractData(response.data);
      if (extracted == null) return <T>[];
      return (extracted as List<dynamic>).map((item) => parser(item)).toList();
    });
  }
}
