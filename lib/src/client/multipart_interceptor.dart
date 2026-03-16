import 'dart:io';

import 'package:dio/dio.dart';

/// Interceptor that automatically handles multipart/form-data requests.
///
/// Features:
/// - Auto-detects `File` or `List<File>` in Map data
/// - Converts to FormData and sets Content-Type to multipart/form-data
/// - Falls back to [defaultContentType] for regular data (default: application/json)
/// - Respects explicitly set Content-Type in request options
///
/// Example:
/// ```dart
/// // Just pass File in your data - interceptor handles the rest
/// await client.post('/upload', data: {
///   'file': File('/path/to/image.jpg'),
///   'name': 'my-image',
/// });
/// ```
class MultipartInterceptor extends Interceptor {
  /// The default content type for non-file requests.
  ///
  /// Defaults to 'application/json'. Set to null to disable.
  final String? defaultContentType;

  /// Creates a [MultipartInterceptor].
  const MultipartInterceptor({
    this.defaultContentType = 'application/json',
  });

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Already FormData - just ensure content type
    if (options.data is FormData) {
      options.contentType ??= 'multipart/form-data';
      handler.next(options);
      return;
    }

    // Check for files in Map data
    if (options.data is Map<String, dynamic>) {
      final data = options.data as Map<String, dynamic>;

      if (_containsFiles(data)) {
        final formData = await _toFormData(data);
        options.data = formData;
        options.contentType = 'multipart/form-data';
        handler.next(options);
        return;
      }
    }

    // Apply default content type for non-null data (if not already set)
    if (options.contentType == null &&
        options.data != null &&
        defaultContentType != null) {
      options.contentType = defaultContentType;
    }

    handler.next(options);
  }

  /// Checks if the map contains any File values.
  bool _containsFiles(Map<String, dynamic> data) {
    for (final value in data.values) {
      if (value is File) return true;
      if (value is List<File>) return true;
      if (value is Map<String, File>) return true;
    }
    return false;
  }

  /// Converts a Map with File values to FormData.
  Future<FormData> _toFormData(Map<String, dynamic> data) async {
    final formMap = <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is File) {
        formMap[key] = await _fileToMultipart(value);
      } else if (value is List<File>) {
        formMap[key] = await Future.wait(
          value.map((f) => _fileToMultipart(f)),
        );
      } else if (value is Map<String, File>) {
        for (final fileEntry in value.entries) {
          formMap[fileEntry.key] = await _fileToMultipart(fileEntry.value);
        }
      } else {
        formMap[key] = value;
      }
    }

    return FormData.fromMap(formMap);
  }

  /// Converts a File to MultipartFile.
  Future<MultipartFile> _fileToMultipart(File file) async {
    final filename = file.path.split('/').last;
    return MultipartFile.fromFile(file.path, filename: filename);
  }
}
