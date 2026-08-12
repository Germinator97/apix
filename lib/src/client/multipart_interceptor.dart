import 'dart:io';

import 'package:dio/dio.dart';

import '../errors/multipart_replay_exception.dart';

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

  /// Key under which the caller's original data map rides on the request, so a
  /// replayed attempt can be given a body of its own.
  ///
  /// A `FormData` is single-use — dio finalizes it into a stream — and two
  /// things in apix replay a request without the caller asking:
  /// `AuthInterceptor` after a token refresh, and `RetryInterceptor` on a
  /// retryable status. Both re-enter the chain with the same `RequestOptions`,
  /// so without this the second attempt carried a body that had already been
  /// consumed.
  static const String multipartSourceKey = '_apix_multipart_source';

  /// Creates a [MultipartInterceptor].
  const MultipartInterceptor({
    this.defaultContentType = 'application/json',
  });

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      // A replay of a request we built: rebuild the body from the caller's
      // map, so this attempt gets a FormData nobody has consumed.
      final source = options.extra[multipartSourceKey];
      if (source is Map<String, dynamic>) {
        options.data = await _toFormData(source);
        options.contentType = 'multipart/form-data';
        handler.next(options);
        return;
      }

      if (options.data is FormData) {
        final form = options.data as FormData;

        // Finalized means this body has already been streamed once, so this is
        // a replay of a FormData apix did not build and cannot rebuild.
        // Failing here names the cause; letting it through raised a StateError
        // that reached the caller as `ApiException: Unknown error`, having
        // replaced the status that triggered the replay in the first place.
        if (form.isFinalized) {
          handler.reject(
            DioException(
              requestOptions: options,
              error: const MultipartReplayException(),
              type: DioExceptionType.unknown,
            ),
          );
          return;
        }

        options.contentType ??= 'multipart/form-data';
        handler.next(options);
        return;
      }

      // Check for files in Map data
      if (options.data is Map<String, dynamic>) {
        final data = options.data as Map<String, dynamic>;

        if (_containsFiles(data)) {
          // Remember the map only when everything in it can be rebuilt. A
          // caller-supplied MultipartFile cannot be, so storing the map would
          // promise a replay that would fail on the second attempt instead of
          // reporting it on the first.
          if (!_containsMultipartFile(data)) {
            options.extra[multipartSourceKey] = data;
          }
          options.data = await _toFormData(data);
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
    } catch (e, st) {
      // Reading a file can fail between two attempts — it may have been moved
      // or deleted since the first one. Surfacing that as a typed failure beats
      // an unhandled async error with no request attached to it.
      handler.reject(
        DioException(
          requestOptions: options,
          error: MultipartReplayException(
            message: 'Failed to build the multipart body: $e',
            originalError: e,
            stackTrace: st,
          ),
          type: DioExceptionType.unknown,
        ),
      );
    }
  }

  /// Whether [value] holds a [MultipartFile] the caller built themselves.
  bool _containsMultipartFile(dynamic value) {
    if (value is MultipartFile) return true;
    if (value is Iterable) return value.any(_containsMultipartFile);
    if (value is Map) return value.values.any(_containsMultipartFile);
    return false;
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
