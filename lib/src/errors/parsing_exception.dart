import 'api_exception.dart';

/// Exception thrown when a response body cannot be parsed.
///
/// This is raised by the typed response methods (`*AndDecode`, `*AndParse`,
/// and their envelope variants) when the user-supplied parser callback or
/// the internal envelope unwrapping fails — for example, on truncated JSON,
/// shape mismatches, or invalid casts.
///
/// It is also raised by the raw verbs (`get`, `post`, …) when a successful
/// response claims JSON and its body does not parse, with the response's
/// [statusCode]. An *error* response whose body does not parse keeps the
/// exception its status calls for — a `401` stays an `UnauthorizedException`
/// — with the body as text in `responseBody`.
///
/// It extends [ApiException] so existing `on ApiException catch` blocks
/// catch it transparently.
///
/// Example:
/// ```dart
/// try {
///   final user = await client.getAndDecode('/users/1', User.fromJson);
/// } on ParsingException catch (e) {
///   // Handle bad payload
/// } on ApiException catch (e) {
///   // Handle other API errors
/// }
/// ```
class ParsingException extends ApiException {
  /// Creates a [ParsingException] with the given [message].
  const ParsingException({
    required super.message,
    super.statusCode,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('ParsingException: $message');
    if (statusCode != null) {
      buffer.write(' (status: $statusCode)');
    }
    return buffer.toString();
  }
}
