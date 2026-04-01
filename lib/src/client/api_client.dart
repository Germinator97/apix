import 'package:dio/dio.dart';

import '../errors/api_exception.dart';
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
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
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
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
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
    return _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
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
    return _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
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
    return _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
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
    return parser(response.data);
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
    final response = await get<Map<String, dynamic>>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return fromJson(_requireData(response));
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
    return parser(response.data);
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
    final response = await post<Map<String, dynamic>>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return fromJson(_requireData(response));
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
    return parser(response.data);
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
    final response = await put<Map<String, dynamic>>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return fromJson(_requireData(response));
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
    return parser(response.data);
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
    final response = await patch<Map<String, dynamic>>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return fromJson(_requireData(response));
  }

  /// Asserts that the response data is non-null and returns it.
  ///
  /// Throws [ApiException] if the response body is null (e.g. 204 No Content).
  Map<String, dynamic> _requireData(Response<Map<String, dynamic>> response) {
    final data = response.data;
    if (data == null) {
      throw ApiException(
        message: 'Expected JSON response body, got null '
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
  /// Expects `responseData` to be a `Map<String, dynamic>` containing
  /// the configured data key. Throws [ApiException] with a clear message if
  /// the response format is unexpected.
  dynamic _extractData(dynamic responseData) {
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
    return parser(_extractData(response.data));
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
    final data = _extractData(response.data);
    return data == null ? null : parser(data);
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
    return fromJson(_extractData(response.data) as Map<String, dynamic>);
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
    final data = _extractData(response.data);
    if (data == null) return null;
    return fromJson(data as Map<String, dynamic>);
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
    return (_extractData(response.data) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((json) => fromJson(json))
        .toList();
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
    final data = _extractData(response.data);
    if (data == null) return null;
    return (data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((json) => fromJson(json))
        .toList();
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
    final data = _extractData(response.data);
    if (data == null) return <T>[];
    return (data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((json) => fromJson(json))
        .toList();
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
    return (_extractData(response.data) as List<dynamic>)
        .map((item) => parser(item))
        .toList();
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
    final data = _extractData(response.data);
    if (data == null) return null;
    return (data as List<dynamic>).map((item) => parser(item)).toList();
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
    final data = _extractData(response.data);
    if (data == null) return <T>[];
    return (data as List<dynamic>).map((item) => parser(item)).toList();
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
    return parser(_extractData(response.data));
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
    final extracted = _extractData(response.data);
    return extracted == null ? null : parser(extracted);
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
    return fromJson(_extractData(response.data) as Map<String, dynamic>);
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
    final extracted = _extractData(response.data);
    if (extracted == null) return null;
    return fromJson(extracted as Map<String, dynamic>);
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
    return (_extractData(response.data) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((json) => fromJson(json))
        .toList();
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
    final extracted = _extractData(response.data);
    if (extracted == null) return null;
    return (extracted as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((json) => fromJson(json))
        .toList();
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
    final extracted = _extractData(response.data);
    if (extracted == null) return <T>[];
    return (extracted as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((json) => fromJson(json))
        .toList();
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
    return (_extractData(response.data) as List<dynamic>)
        .map((item) => parser(item))
        .toList();
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
    final extracted = _extractData(response.data);
    if (extracted == null) return null;
    return (extracted as List<dynamic>).map((item) => parser(item)).toList();
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
    final extracted = _extractData(response.data);
    if (extracted == null) return <T>[];
    return (extracted as List<dynamic>).map((item) => parser(item)).toList();
  }
}
