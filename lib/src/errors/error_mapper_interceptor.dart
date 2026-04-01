import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'http_exception.dart';
import 'network_exception.dart';

/// Interceptor that transforms [DioException] into typed [ApiException].
///
/// This interceptor ensures that all errors thrown by the API client
/// are properly typed [ApiException] subclasses, making error handling
/// predictable and type-safe.
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users');
/// } on UnauthorizedException catch (e) {
///   // Handle 401
/// } on TimeoutException catch (e) {
///   // Handle timeout
/// } on ApiException catch (e) {
///   // Handle other API errors
/// }
/// ```
class ErrorMapperInterceptor extends Interceptor {
  /// Creates an [ErrorMapperInterceptor].
  const ErrorMapperInterceptor();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final apiException = mapDioException(err);

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: apiException,
        stackTrace: err.stackTrace,
      ),
    );
  }

  /// Maps a [DioException] to the appropriate [ApiException] subtype.
  static ApiException mapDioException(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
        return TimeoutException(
          message: err.message ?? 'Connection timeout',
          duration: err.requestOptions.connectTimeout,
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.sendTimeout:
        return TimeoutException(
          message: err.message ?? 'Send timeout',
          duration: err.requestOptions.sendTimeout,
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.receiveTimeout:
        return TimeoutException(
          message: err.message ?? 'Receive timeout',
          duration: err.requestOptions.receiveTimeout,
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.connectionError:
        return ConnectionException(
          message: err.message ?? 'Connection failed',
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.badResponse:
        return _mapBadResponse(err);

      case DioExceptionType.cancel:
        return ApiException(
          message: 'Request cancelled',
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.badCertificate:
        return NetworkException(
          message: err.message ?? 'Bad certificate',
          originalError: err,
          stackTrace: err.stackTrace,
        );

      case DioExceptionType.unknown:
        // Check if the inner error is already an ApiException
        if (err.error is ApiException) {
          return err.error as ApiException;
        }
        return ApiException(
          message: err.message ?? 'Unknown error',
          originalError: err.error ?? err,
          stackTrace: err.stackTrace,
        );
    }
  }

  static ApiException _mapBadResponse(DioException err) {
    final response = err.response;
    final statusCode = response?.statusCode ?? 0;
    final message = _extractMessage(response);

    return switch (statusCode) {
      401 => UnauthorizedException(
          message: message,
          responseBody: response?.data,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
      403 => ForbiddenException(
          message: message,
          responseBody: response?.data,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
      404 => NotFoundException(
          message: message,
          responseBody: response?.data,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
      _ => HttpException(
          message: message,
          statusCode: statusCode,
          responseBody: response?.data,
          originalError: err,
          stackTrace: err.stackTrace,
        ),
    };
  }

  static String _extractMessage(Response<dynamic>? response) {
    final data = response?.data;

    if (data is Map) {
      // Common API message field names (flat structure)
      final message =
          data['message'] ?? data['detail'] ?? data['error_description'];

      if (message is String) {
        return message;
      }

      // Nested error object: { "error": { "message": "..." } }
      final error = data['error'];
      if (error is Map) {
        final nestedMessage =
            error['message'] ?? error['detail'] ?? error['description'];
        if (nestedMessage is String) {
          return nestedMessage;
        }
      }

      // Flat error string: { "error": "Something went wrong" }
      if (error is String) {
        return error;
      }
    }

    return 'HTTP ${response?.statusCode ?? 'error'}';
  }
}
