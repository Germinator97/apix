import 'package:dio/dio.dart';

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
  /// Unlike [getAndDecode], accepts any response type (not just JSON objects).
  ///
  /// Example:
  /// ```dart
  /// // Parse JSON object
  /// final user = await client.getAndParse('/users/1', User.fromJson);
  ///
  /// // Parse primitive
  /// final count = await client.getAndParse('/users/count', (data) => data as int);
  ///
  /// // Parse with DateTime
  /// final date = await client.getAndParse(
  ///   '/server/time',
  ///   (data) => DateTime.parse(data as String),
  /// );
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

  /// Sends a GET request and parses the response, returning null if response is null.
  ///
  /// Example:
  /// ```dart
  /// final user = await client.getAndParseOrNull('/users/1', User.fromJson);
  /// if (user == null) print('User not found');
  /// ```
  Future<T?> getAndParseOrNull<T>(
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
    return response.data == null ? null : parser(response.data);
  }

  /// Sends a GET request and deserializes a JSON object response.
  ///
  /// Example:
  /// ```dart
  /// final user = await client.getAndDecode(
  ///   '/users/1',
  ///   (json) => User.fromJson(json),
  /// );
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
    return fromJson(response.data!);
  }

  /// Sends a GET request and deserializes a JSON object, returning null if empty.
  Future<T?> getAndDecodeOrNull<T>(
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
    if (response.data == null) return null;
    return fromJson(response.data as Map<String, dynamic>);
  }

  /// Sends a POST request and parses the response using [parser].
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

  /// Sends a POST request and parses the response, returning null if empty.
  Future<T?> postAndParseOrNull<T>(
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
    return response.data == null ? null : parser(response.data);
  }

  /// Sends a POST request and deserializes the response.
  ///
  /// Example:
  /// ```dart
  /// final user = await client.postAndDecode(
  ///   '/users',
  ///   {'name': 'John'},
  ///   (json) => User.fromJson(json),
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
    return fromJson(response.data!);
  }

  /// Sends a POST request and deserializes, returning null if empty.
  Future<T?> postAndDecodeOrNull<T>(
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
    if (response.data == null) return null;
    return fromJson(response.data as Map<String, dynamic>);
  }

  /// Sends a PUT request and parses the response using [parser].
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
    return fromJson(response.data!);
  }

  /// Sends a PATCH request and parses the response using [parser].
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
    return fromJson(response.data!);
  }

  /// Sends a GET request and deserializes a list response.
  ///
  /// Example:
  /// ```dart
  /// final users = await client.getListAndDecode(
  ///   '/users',
  ///   (json) => User.fromJson(json),
  /// );
  /// ```
  Future<List<T>> getListAndDecode<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<List<dynamic>>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return response.data!
        .cast<Map<String, dynamic>>()
        .map((json) => fromJson(json))
        .toList();
  }

  /// Sends a GET request and parses a list response using [parser].
  ///
  /// More flexible than [getListAndDecode], works with any list item type.
  ///
  /// Example:
  /// ```dart
  /// final ids = await client.getListAndParse('/user-ids', (item) => item as int);
  /// ```
  Future<List<T>> getListAndParse<T>(
    String path,
    T Function(dynamic item) parser, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await get<List<dynamic>>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
    return response.data!.map((item) => parser(item)).toList();
  }

  /// Sends a GET request and deserializes a list, returning null if response is null.
  ///
  /// Example:
  /// ```dart
  /// final users = await client.getListAndDecodeOrNull('/users', User.fromJson);
  /// if (users == null) print('No data');
  /// ```
  Future<List<T>?> getListAndDecodeOrNull<T>(
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
    if (response.data == null) return null;
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((json) => fromJson(json))
        .toList();
  }

  /// Sends a GET request and deserializes a list, returning empty list if null.
  ///
  /// Example:
  /// ```dart
  /// final users = await client.getListAndDecodeOrEmpty('/users', User.fromJson);
  /// // Always returns a list, never null
  /// ```
  Future<List<T>> getListAndDecodeOrEmpty<T>(
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
    if (response.data == null) return <T>[];
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((json) => fromJson(json))
        .toList();
  }

  /// Sends a GET request and parses a list, returning null if response is null.
  Future<List<T>?> getListAndParseOrNull<T>(
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
    if (response.data == null) return null;
    return (response.data as List<dynamic>)
        .map((item) => parser(item))
        .toList();
  }

  /// Sends a GET request and parses a list, returning empty list if null.
  Future<List<T>> getListAndParseOrEmpty<T>(
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
    if (response.data == null) return <T>[];
    return (response.data as List<dynamic>)
        .map((item) => parser(item))
        .toList();
  }
}
