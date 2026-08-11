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

  /// Checks if the value is a [File] or contains [File] instances.
  bool _isOrContainsFile(dynamic value) {
    if (value is File) return true;
    if (value is List) return value.any(_isOrContainsFile);
    if (value is Map) return value.values.any(_isOrContainsFile);
    return false;
  }

  /// Checks if the map contains any File values.
  bool _containsFiles(Map<String, dynamic> data) {
    return data.values.any(_isOrContainsFile);
  }

  /// Converts a Map holding [File] values into [FormData].
  ///
  /// The only transformation applied is `File` → [MultipartFile]. **The shape
  /// of the data is left exactly as the caller wrote it**, and `FormData` does
  /// the encoding.
  ///
  /// That division of labour is the fix for three silent losses. The previous
  /// implementation flattened the map itself, one level deep, while
  /// [_isOrContainsFile] detected files at *any* depth — so anything below the
  /// first level was dropped without a word:
  ///
  /// - `{'user': {'avatar': File, 'name': 'John'}}` sent the file under a bare
  ///   `avatar`, losing both `name` and the `user` nesting;
  /// - `{'a': {'b': {'file': File}}}` sent an **empty body** — request
  ///   accepted, `200` returned, nothing uploaded;
  /// - `{'items': [File, 'caption']}` sent the file and dropped the caption.
  ///
  /// `FormData.fromMap` walks maps and lists recursively through dio's
  /// `encodeMap`, producing `user[avatar]`, `a[b][file]`, and — for a list of
  /// scalars under `ListFormat.multi` — the repeated bare key backends expect.
  /// Inheriting those conventions is deliberate: inventing a second bracket
  /// syntax here would eventually disagree with the one dio uses everywhere
  /// else.
  Future<FormData> _toFormData(Map<String, dynamic> data) async {
    final converted = await _convertFiles(data);
    return FormData.fromMap(converted as Map<String, dynamic>);
  }

  /// Recursively replaces every [File] with a [MultipartFile], preserving maps,
  /// lists, and every value that is neither.
  Future<dynamic> _convertFiles(dynamic value) async {
    if (value is File) return _fileToMultipart(value);

    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        result['${entry.key}'] = await _convertFiles(entry.value);
      }
      return result;
    }

    if (value is Iterable) {
      final result = <dynamic>[];
      for (final item in value) {
        result.add(await _convertFiles(item));
      }
      return result;
    }

    return value;
  }

  /// Converts a File to MultipartFile.
  Future<MultipartFile> _fileToMultipart(File file) async {
    final filename = file.uri.pathSegments.last;
    return MultipartFile.fromFile(file.path, filename: filename);
  }
}
