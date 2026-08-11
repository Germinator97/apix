import 'package:dio/dio.dart';

import 'response_validator_interceptor.dart';

/// Configuration for ApiClient.
///
/// Example:
/// ```dart
/// final config = ApiClientConfig(
///   baseUrl: 'https://api.example.com',
///   timeout: Duration(seconds: 60),
///   headers: {'X-Custom': 'value'},
/// );
/// ```
class ApiClientConfig {
  /// The base URL for all requests.
  final String baseUrl;

  /// Connection timeout duration.
  ///
  /// Defaults to 30 seconds.
  final Duration connectTimeout;

  /// Receive timeout duration.
  ///
  /// Defaults to 30 seconds.
  final Duration receiveTimeout;

  /// Send timeout duration.
  ///
  /// Defaults to 30 seconds.
  final Duration sendTimeout;

  /// Default headers to include in all requests.
  final Map<String, dynamic>? headers;

  /// Default content type for requests.
  ///
  /// Defaults to 'application/json'. Set to null to disable auto content-type.
  /// This is automatically overridden when sending FormData (multipart).
  final String? defaultContentType;

  /// Custom Dio interceptors to add.
  ///
  /// Appended **after** everything the factory installs — auth, retry,
  /// deduplication, cache, and every observer — and before the error mapper.
  /// That is the right place for a custom interceptor: it sees the final
  /// request and the final response, after apix has done its work.
  ///
  /// ## One caveat, for *re-entrant* interceptors
  ///
  /// `CacheInterceptor` and `DeduplicationInterceptor` are re-entrant: they
  /// call `dio.fetch(...)` internally, which restarts the whole chain for the
  /// request they actually send. The factory places them **before** the
  /// observers so that inner pass is not logged a second time.
  ///
  /// Passing one here puts it after the observers instead, and the inner pass
  /// is observed too. Measured, so it is not a guess: one call becomes two
  /// `→ Request` log lines and one extra request breadcrumb. Network traffic,
  /// metrics and response logs are unchanged — it is log noise, not doubled
  /// telemetry.
  ///
  /// So prefer `cacheConfig` / `deduplicationConfig`, and reach for the
  /// instance through `ApiClient.cacheInterceptor` when you need the
  /// invalidation API. Wiring one here still works, and is worth it if you
  /// need a placement the factory does not offer.
  final List<Interceptor>? interceptors;

  /// The key used to extract data from envelope responses.
  ///
  /// When using `*Data` methods (e.g. `getAndDecodeData`), the response
  /// is expected to be wrapped: `{ "data": { ... } }`.
  /// This key specifies which field contains the actual payload.
  ///
  /// Defaults to `'data'`.
  final String dataKey;

  /// The key used to extract the application-level error code from error
  /// response bodies.
  ///
  /// With the envelope `{ "code": "...", "message": "...", "data": null }`,
  /// the default reads `code` and exposes it as `ApiException.code`, so call
  /// sites can branch on a stable business code instead of an HTTP status that
  /// may drift between server revisions.
  ///
  /// Defaults to `'code'`.
  ///
  /// ⚠️ That default is also the field plenty of envelopes use for the **HTTP
  /// status** (`{"code": 401, "message": "..."}`). A status read as a business
  /// code is worse than no code at all — it looks like one. apix drops any
  /// value equal to the response status, so this stays safe out of the box,
  /// but if your API publishes real codes under a different name, say so here
  /// (`errorCodeKey: 'errorCode'`) rather than relying on the guard.
  final String errorCodeKey;

  /// When `true`, typed-decode methods (`*AndDecode`, `*AndDecodeData`,
  /// `*ListAndDecode...`) verify that the response's `Content-Type` header
  /// starts with `application/json` and throw
  /// `UnexpectedContentTypeException` otherwise.
  ///
  /// Useful to detect captive portals or backends that incorrectly return
  /// HTML for an API endpoint. Defaults to `false` for backward compatibility.
  /// `*AndParse` methods are unaffected.
  final bool strictContentType;

  /// Optional callback to validate 2xx responses.
  ///
  /// Useful for legacy APIs that report business errors via HTTP 200 with a
  /// `{"success": false, ...}` body. Return an `ApiException` subclass to
  /// have the request fail with that exception, or `null` to let the
  /// response pass through.
  ///
  /// Only invoked on 2xx responses; 4xx/5xx still go through
  /// `ErrorMapperInterceptor`.
  final ResponseValidator? responseValidator;

  /// Creates an [ApiClientConfig].
  ///
  /// Only [baseUrl] is required. All other options have sensible defaults.
  const ApiClientConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.headers,
    this.defaultContentType = 'application/json',
    this.interceptors,
    this.dataKey = 'data',
    this.errorCodeKey = 'code',
    this.strictContentType = false,
    this.responseValidator,
  });

  /// Creates a copy of this config with the given fields replaced.
  ///
  /// **A `null` argument means "keep the current value", never "clear it".**
  /// Passing `null` explicitly cannot remove a callback or an optional field —
  /// build a fresh config for that. The usual Dart limitation, stated because
  /// the alternative is discovering it from a callback that kept firing after
  /// you thought you had removed it.
  ApiClientConfig copyWith({
    String? baseUrl,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Map<String, dynamic>? headers,
    String? defaultContentType,
    List<Interceptor>? interceptors,
    String? dataKey,
    String? errorCodeKey,
    bool? strictContentType,
    ResponseValidator? responseValidator,
  }) {
    return ApiClientConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      headers: headers ?? this.headers,
      defaultContentType: defaultContentType ?? this.defaultContentType,
      interceptors: interceptors ?? this.interceptors,
      dataKey: dataKey ?? this.dataKey,
      errorCodeKey: errorCodeKey ?? this.errorCodeKey,
      strictContentType: strictContentType ?? this.strictContentType,
      responseValidator: responseValidator ?? this.responseValidator,
    );
  }
}
