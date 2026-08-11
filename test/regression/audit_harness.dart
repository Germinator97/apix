import 'dart:convert';
import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';

/// Shared fixtures for the regression suite.
///
/// Every test under `test/regression/` pins one defect found by the 5.0
/// audit. They are integration tests on purpose: each defect lived at a
/// *junction* between two interceptors that were both correct on their own, so
/// none of them is reachable from a unit test of either half.
///
/// The audit's own finding IDs (`B1`…`B5`, `M6`…`M14`) are carried in the test
/// names, so a failure points straight at the entry that explains it.

/// An [HttpClientAdapter] that answers from a script and records what it saw.
///
/// [responder] receives the request and its 0-indexed call number, which is
/// what lets a test say "fail the first time, succeed the second" without
/// keeping state of its own.
///
/// Note the signature is byte-identical across the whole declared dio range
/// (`>=5.4.0 <7.0.0`), so this harness compiles on both CI bounds.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.responder);

  /// Builds the response for a given request and call index.
  final ResponseBody Function(RequestOptions options, int callIndex) responder;

  /// Every request that reached the adapter, in order.
  ///
  /// Counting these is how most of these tests prove a cache hit: the
  /// observable difference between "served from cache" and "fetched again" is
  /// whether the adapter was called at all.
  final List<RequestOptions> seen = [];

  /// How many requests actually went out.
  int get callCount => seen.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = seen.length;
    seen.add(options);
    return responder(options, index);
  }

  @override
  void close({bool force = false}) {}
}

/// A JSON response carrying [body], with any extra [headers] merged in.
ResponseBody jsonResponse(
  Object? body,
  int statusCode, {
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      ...?headers,
    },
  );
}

/// A response with an explicit [contentType], used where the *type* of the
/// body — not its shape — is what a test is about.
ResponseBody textResponse(
  String body,
  int statusCode, {
  String contentType = 'text/plain',
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      Headers.contentTypeHeader: [contentType],
      ...?headers,
    },
  );
}

/// The response body as a JSON object.
///
/// Exists so tests never index a `dynamic` — `avoid_dynamic_calls` is fatal
/// here, and a cast at the call site would read as noise in every assertion.
Map<String, dynamic> bodyOf(Response<dynamic> response) =>
    response.data as Map<String, dynamic>;

/// A [TokenProvider] backed by plain fields, so a test can change identity
/// mid-flight the way a logout/login does.
class StubTokenProvider implements TokenProvider {
  StubTokenProvider(
      {this.accessToken = 'token-A', this.refreshToken = 'ref-A'});

  /// The token handed to the next request. Assign to it to switch identity.
  String? accessToken;

  /// The token the refresh flow will present.
  String? refreshToken;

  /// Every `saveTokens` call, so a test can assert what a refresh persisted.
  final List<(String, String)> saved = [];

  /// Whether `clearTokens` was called.
  bool cleared = false;

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> saveTokens(String access, String refresh) async {
    saved.add((access, refresh));
    accessToken = access;
    refreshToken = refresh;
  }

  @override
  Future<void> clearTokens() async {
    cleared = true;
    accessToken = null;
    refreshToken = null;
  }
}
