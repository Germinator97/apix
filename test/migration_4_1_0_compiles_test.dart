@TestOn('vm')
library;

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers, by compiling, the question a consumer asks before a major:
/// **what breaks when I upgrade?**
///
/// Every declaration below is written the way apix 4.1.0 documented it. If a
/// symbol were removed, a required parameter added, or a signature narrowed,
/// this file would stop compiling — which is a stronger answer than a sentence
/// in a changelog saying nothing breaks.
///
/// It deliberately does **not** assert behaviour. 5.0.0 changes defaults, and
/// those changes are the point; what this file pins is that a consumer meets
/// them at runtime, having read the changelog, rather than at build time,
/// having read a compiler error.
void main() {
  test('a consumer written against 4.1.0 still compiles against 5.0.0', () {
    // ---- the factory, with every 4.1.0 option ----
    final client = ApiClientFactory.create(
      baseUrl: 'https://api.test',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      defaultContentType: 'application/json',
      headers: const {'X-App': 'demo'},
      authConfig: AuthConfig(
        tokenProvider: _Tokens(),
        refreshEndpoint: '/auth/refresh',
        refreshHeaders: const {'X-Refresh': '1'},
        refreshTokenBodyKey: 'refresh_token',
        headerName: 'Authorization',
        headerPrefix: 'Bearer',
        refreshStatusCodes: const [401],
        onTokenRefreshed: (response) async {},
        onAuthFailure: (provider, error) async {},
        onRefresh: (provider) async => true,
      ),
      retryConfig: const RetryConfig(
        maxAttempts: 3,
        retryStatusCodes: [500, 502, 503, 504],
        baseDelayMs: 1000,
        multiplier: 2.0,
        maxDelayMs: 30000,
        respectRetryAfter: true,
        jitter: 0.2,
        retryableMethods: {'GET', 'HEAD', 'PUT', 'DELETE'},
      ),
      onRetry: (attempt) => <Object?>[
        attempt.attempt,
        attempt.delay,
        attempt.cause,
        attempt.statusCode,
      ],
      cacheConfig: CacheConfig(
        storage: InMemoryCacheStorage(maxEntries: 50),
        strategy: CacheStrategy.networkFirst,
        defaultTtl: const Duration(minutes: 5),
        cacheErrors: false,
        cacheableMethods: const ['GET'],
        enableDeduplication: true,
        deduplicateMethods: const ['GET'],
      ),
      deduplicationConfig: const DeduplicationConfig(
        enabled: true,
        methods: ['GET'],
      ),
      loggerConfig: LoggerConfig(
        level: LogLevel.info,
        logRequestHeaders: true,
        logErrors: true,
        maxBodyLength: 1024,
        redactedHeaders: const ['Authorization'],
        includeTimestamp: true,
        logHandler: (entry) => <Object?>[
          entry.level,
          entry.message,
          entry.statusCode,
          entry.durationMs,
          entry.body,
          entry.error,
        ],
      ),
      errorTrackingConfig: ErrorTrackingConfig(
        environment: 'test',
        captureStatusCodes: const {500, 503},
        captureRequestBody: false,
        redactedHeaders: const ['Authorization'],
        maxBodyLength: 1024,
        onError: (exception, {stackTrace, extra, tags}) async {},
        onBreadcrumb: (data) {},
      ),
      metricsConfig: MetricsConfig(
        trackRequestSize: true,
        trackResponseSize: true,
        requestIdGenerator: () => 'id',
        onMetrics: (metrics) => <Object?>[
          metrics.requestId,
          metrics.durationMs,
          metrics.success,
          metrics.toMap(),
        ],
        onBreadcrumb: (breadcrumb) => breadcrumb.toMap(),
      ),
      tracingConfig: TracingConfig(startSpan: (op, description) => null),
      dataKey: 'data',
      errorCodeKey: 'code',
      strictContentType: true,
      responseValidator: (response) => null,
      interceptors: const [],
      httpClientAdapter: _Adapter(),
    );

    // ---- the surface a call site touches ----
    expect(client.baseUrl, 'https://api.test');
    expect(client.dio, isNotNull);
    expect(client.config.dataKey, 'data');
    client.close();

    // ---- per-request extensions ----
    final options = RequestOptions(path: '/x')
      ..disableRetry()
      ..forceRetry()
      ..noCache()
      ..setCacheStrategy(CacheStrategy.cacheFirst)
      ..recordStartTime();
    expect(options.isNoRetry, isTrue);
    expect(options.isForceRetry, isTrue);
    expect(options.durationMs, isNotNull);
    expect(options.extra[noRetryKey], isTrue);
    expect(options.extra[forceRetryKey], isTrue);

    // ---- the exception hierarchy, as 4.1.0 documented it ----
    const exceptions = <ApiException>[
      ApiException(message: 'x'),
      HttpException(message: 'x', statusCode: 400),
      ClientException(message: 'x', statusCode: 400),
      UnauthorizedException(),
      ForbiddenException(),
      NotFoundException(),
      TooManyRequestsException(retryAfter: Duration(seconds: 30)),
      ServerException(message: 'x', statusCode: 500),
      NetworkException(message: 'x'),
      TimeoutException(message: 'x'),
      ConnectionException(message: 'x'),
      ParsingException(message: 'x'),
      UnexpectedContentTypeException(
        expectedContentType: 'application/json',
        actualContentType: 'text/html',
        statusCode: 200,
      ),
      TokenProviderException(
        operation: TokenProviderOperation.read,
        message: 'x',
      ),
      CacheException('x'),
      AuthException('x'),
    ];
    expect(exceptions.first.message, 'x');
    expect(exceptions.last.code, isNull);

    // ---- Result ----
    const Result<int, ApiException> result = Result.success(1);
    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, 1);
    expect(result.errorOrNull, isNull);
    expect(result.getOrElse(() => 0), 1);
    expect(result.fold(onSuccess: (v) => v, onFailure: (e) => 0), 1);
    result.when(success: (_) {}, failure: (_) {});
    expect(result.map((v) => v).valueOrNull, 1);
    expect(result.flatMap<int>(Result.success).valueOrNull, 1);
    expect(result.mapError<ApiException>((e) => e).valueOrNull, 1);
    expect(result.recover((e) => 0).valueOrNull, 1);

    // ---- storages, including a consumer's own ----
    final storages = <CacheStorage>[
      InMemoryCacheStorage(),
      EncryptedCacheStorage(
        delegate: InMemoryCacheStorage(),
        encrypt: (plain) => plain,
        decrypt: (sealed) => sealed,
      ),
      _CustomStorage(),
    ];
    expect(storages, hasLength(3));

    // ---- entries ----
    final entry = CacheEntry.withTtl(
      data: '{}',
      statusCode: 200,
      ttl: const Duration(minutes: 1),
      etag: 'W/"1"',
      headers: const {'x': 'y'},
    );
    expect(entry.isValid, isTrue);
    expect(entry.isExpired, isFalse);
    expect(entry.remainingTtl, isNotNull);
    expect(entry.copyWith(statusCode: 201).statusCode, 201);
    expect(CacheEntry.tryFromJson(entry.toJson()), isNotNull);

    // ---- secure storage ----
    final provider = SecureTokenProvider(
      accessTokenKey: 'a',
      refreshTokenKey: 'r',
    );
    expect(provider.storage, isA<SecureStorageService>());
  });
}

/// A `CacheStorage` written by a consumer against the 4.1.0 interface.
///
/// The one shape that would break loudly if the interface had gained a method:
/// an implementation apix cannot see and cannot update.
class _CustomStorage implements CacheStorage {
  final _entries = <String, CacheEntry>{};

  @override
  Future<CacheEntry?> get(String key) async => _entries[key];

  @override
  Future<void> set(String key, CacheEntry entry) async => _entries[key] = entry;

  @override
  Future<void> remove(String key) async => _entries.remove(key);

  @override
  Future<void> clear() async => _entries.clear();

  @override
  Future<bool> has(String key) async => _entries[key]?.isValid ?? false;

  @override
  Future<List<String>> keys() async => _entries.keys.toList();

  @override
  Future<int> removeWhere(bool Function(String key) predicate) async {
    final gone = _entries.keys.where(predicate).toList();
    for (final key in gone) {
      _entries.remove(key);
    }
    return gone.length;
  }

  @override
  Future<int> removeByPrefix(String prefix) =>
      removeWhere((key) => key.startsWith(prefix));
}

class _Tokens implements TokenProvider {
  @override
  Future<String?> getAccessToken() async => 'a';

  @override
  Future<String?> getRefreshToken() async => 'r';

  @override
  Future<void> saveTokens(String access, String refresh) async {}

  @override
  Future<void> clearTokens() async {}
}

class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async =>
      ResponseBody.fromString('{}', 200);

  @override
  void close({bool force = false}) {}
}
