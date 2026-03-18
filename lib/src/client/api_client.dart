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

  /// Sends a GET request and deserializes the response.
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
}
