import 'api_exception.dart';

/// Thrown when a multipart request has to be sent a second time and apix
/// cannot rebuild its body.
///
/// A `FormData` is single-use: dio turns it into a stream and marks it
/// finalized, so replaying the *same* instance throws. Two things in apix
/// replay a request without the caller asking — `AuthInterceptor` after a
/// token refresh, and `RetryInterceptor` on a retryable status — and both hand
/// back the original `RequestOptions`.
///
/// When the caller passed a plain `Map` containing `File`s, apix keeps that map
/// and builds a fresh `FormData` for each attempt, so the replay simply works.
/// This exception is raised only where that is impossible: the body was handed
/// over as a `FormData` (or a `MultipartFile`) that apix did not build and
/// cannot rebuild.
///
/// ## Why this is an exception rather than a silent skip
///
/// Before it existed, the replay went ahead and dio threw a `StateError`. That
/// error reached `ErrorMapperInterceptor` as a `DioException` of type
/// `unknown`, which maps to `ApiException: Unknown error` — so an upload that
/// hit an expired token failed with a message naming neither the upload, nor
/// the token, nor the replay. Worse, on a retryable `5xx` the replay's
/// `StateError` *replaced* the server's status: a `500` came back to the caller
/// as `Unknown error`, and `on ServerException catch` stopped matching.
///
/// ```dart
/// on MultipartReplayException catch (e) {
///   // Send a Map of Files instead, or opt this request out of replay.
/// }
/// ```
class MultipartReplayException extends ApiException {
  /// Creates a [MultipartReplayException].
  const MultipartReplayException({
    super.message = 'This multipart request cannot be replayed: its body was '
        'supplied as a FormData, which is single-use. Pass a Map containing '
        'File values so apix can rebuild the body for each attempt, or opt the '
        'request out of replay with RequestOptions.disableRetry().',
    super.statusCode,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => 'MultipartReplayException: $message';
}
