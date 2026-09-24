import 'api_exception.dart';

/// Exception thrown when a typed-decode method receives a response whose
/// `Content-Type` header does not match the expected media type.
///
/// Two opt-ins raise it: `ApiClientConfig.strictContentType` for the JSON
/// shapes, and the `expectedContentTypes` of a binary download
/// (`getAndReadBytes` and its verbs), checked on any non-empty body. The most common
/// trigger is a captive Wi-Fi portal (hotel, airport) returning HTML 200 in
/// place of the expected JSON payload — without this check, that HTML would
/// be funnelled into `fromJson` and surface as a confusing parse error.
///
/// Extends [ApiException] so existing `on ApiException catch` blocks catch
/// it transparently.
///
/// Example:
/// ```dart
/// try {
///   final user = await client.getAndDecode('/me', User.fromJson);
/// } on UnexpectedContentTypeException catch (e) {
///   // Likely a captive portal — surface a "check your network" UI.
/// }
/// ```
class UnexpectedContentTypeException extends ApiException {
  /// The content type the call expected (e.g. `application/json`) — or, for a
  /// binary download given several, all of them joined by `", "`.
  final String expectedContentType;

  /// The content type actually received, or `null` if the header was absent.
  final String? actualContentType;

  /// Creates an [UnexpectedContentTypeException].
  const UnexpectedContentTypeException({
    required this.expectedContentType,
    required this.actualContentType,
    required super.statusCode,
    super.message = 'Unexpected Content-Type',
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'UnexpectedContentTypeException: expected $expectedContentType, '
        'got ${actualContentType ?? "(none)"} (status: $statusCode)';
  }
}
