/// Apix Example
///
/// This example demonstrates the basic usage of the apix package,
/// including SecureTokenProvider for secure token storage.
library;

import 'dart:io';

import 'package:apix/apix.dart';
import 'package:flutter/material.dart';

/// Sentry wiring, shown separately because it belongs in your real entry
/// point: `SentrySetup.init` takes the `appRunner` that starts the app.
///
/// ```dart
/// void main() async {
///   SentryWidgetsFlutterBinding.ensureInitialized();
///   await setupSentry(() async => runApp(const MyApp()));
/// }
/// ```
/// The cipher used by [EncryptedCacheStorage] below.
///
/// Deliberately left abstract, and deliberately **not** given a toy
/// implementation here: a base64 "encryption" in an example is the kind of
/// thing that gets copied into production. Back it with real crypto — the
/// `encrypt` package, or a key held in the platform keystore/Keychain — and
/// assign it before building the client.
///
/// apix never sees your key: it only calls these two functions.
abstract class AppCipher {
  /// Encrypts [plaintext] before it reaches the cache storage.
  String seal(String plaintext);

  /// Reverses [seal]. Must throw on a wrong key rather than return garbage —
  /// apix treats a throw as a cache miss and purges the entry.
  String open(String sealed);
}

/// Supplied by your app at startup.
late final AppCipher appCipher;

Future<void> setupSentry(Future<void> Function() appRunner) {
  return SentrySetup.init(
    options: SentrySetupOptions(
      dsn: 'https://xxx@xxx.ingest.sentry.io/xxx',
      environment: 'production',
      // (v2.2.0+) Escape hatch for SentryFlutterOptions apix does not expose.
      // Runs LAST, after every apix default, so it can override anything —
      // including beforeSend. To compose with apix's network-noise filter
      // instead of replacing it, use customBeforeSend.
      //
      // Note the convenience factories (SentrySetupOptions.production /
      // .development) do NOT forward this callback, which is why the options
      // are spelled out here.
      configureOptions: (sentryOptions) {
        sentryOptions.maxBreadcrumbs = 200;
      },
    ),
    appRunner: appRunner,
  );
}

/// Simple example showing API client creation and usage.
void main() async {
  // ============================================================
  // SECURE TOKEN STORAGE
  // ============================================================
  // SecureTokenProvider uses flutter_secure_storage under the hood
  final tokenProvider = SecureTokenProvider();

  // Where the persistent cache lives. In a real app this comes from
  // `path_provider`: `final cacheDir = await getTemporaryDirectory();`
  // apix takes the directory rather than resolving it, so it needs no
  // dependency on path_provider itself.
  final cacheDir = Directory.systemTemp;

  // Create an API client with authentication and retry
  final client = ApiClientFactory.create(
    baseUrl: 'https://api.example.com',
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    // (v2.1.0+) Opt-in: throw UnexpectedContentTypeException when *AndDecode
    // receives a non-JSON response. Useful to detect captive portals.
    strictContentType: false,
    // (v2.1.0+) Hook for legacy APIs that signal errors via HTTP 200 with
    // a `{"success": false, ...}` body. Return an ApiException to fail.
    // responseValidator: (response) {
    //   final body = response.data;
    //   if (body is Map && body['success'] == false) {
    //     return ApiException(
    //       message: body['message'] as String? ?? 'Unknown error',
    //       statusCode: response.statusCode,
    //     );
    //   }
    //   return null;
    // },
    // Authentication configuration (v1.0.1+)
    authConfig: AuthConfig(
      tokenProvider: tokenProvider,
      // Simplified refresh flow (recommended)
      refreshEndpoint: '/auth/refresh',
      onTokenRefreshed: (response) async {
        final data = response.data as Map<String, dynamic>;
        await tokenProvider.saveTokens(
          data['access_token'] as String,
          data['refresh_token'] as String,
        );
      },
      // Called when refresh fails on a real auth error (e.g. refresh token
      // expired). Clear tokens and redirect to login.
      // (v2.1.0+) NOT called on network failures (offline, timeout) — the
      // original request gets NetworkException instead, no spurious logout.
      onAuthFailure: (tokenProvider, error) async {
        debugPrint('Auth failed: $error');
        await tokenProvider.clearTokens();
        // router.go('/login');
      },
    ),
    // Retry configuration
    retryConfig: const RetryConfig(
      maxAttempts: 3,
      retryStatusCodes: [500, 502, 503, 504],
      maxDelayMs: 30000, // Cap at 30s
      // (v2.1.0+) Honor Retry-After header on 429/503 (RFC 7231 §7.1.3).
      // Default is true; set false to always use exponential backoff.
      respectRetryAfter: true,
      // (v2.3.0+) Only idempotent methods are retried by default (RFC 7231
      // §4.2.2). POST/PATCH are excluded so a 5xx after a committed write
      // (e.g. a gateway 502/504 on a payment) is never replayed into a
      // duplicate. Override the set to opt a method in globally.
      retryableMethods: {'GET', 'HEAD', 'OPTIONS', 'TRACE', 'PUT', 'DELETE'},
      // (v4.0.0+) Spreads each backoff across ±20 % of itself. ON by default:
      // without it, every client that failed in the same outage second retries
      // at the same instants and meets the recovering server with a spike.
      // Set 0.0 for the old, strictly deterministic sequence.
      jitter: 0.2,
    ),
    // (v4.0.0+) Fires before each retry waits. Without it a retry storm is
    // invisible — only the final failure ever surfaces.
    //
    // (v4.1.0+) Like every observation callback here, this one cannot break
    // the request: if it throws, apix swallows it and the request carries on.
    // Same for logHandler, onMetrics, onBreadcrumb, onError and startSpan.
    onRetry: (attempt) => debugPrint(
      'retry #${attempt.attempt} in ${attempt.delay.inMilliseconds}ms '
      '(status ${attempt.statusCode})',
    ),
    // Cache configuration (v1.0.1+)
    cacheConfig: CacheConfig(
      // networkFirst is the default: fresh data, with the cache used only as
      // an offline fallback. cacheFirst is the opposite trade — it paints
      // instantly from the cache, serving it even when expired (flagged
      // `isStale`) while a background request refreshes it.
      strategy: CacheStrategy.networkFirst,
      defaultTtl: const Duration(minutes: 5),
      // (v3.0.0+) Survives restarts, unlike the default InMemoryCacheStorage
      // which starts empty on every cold start — precisely when the wait is
      // most visible. You supply the directory (here from `path_provider`),
      // so apix needs no extra dependency of its own.
      //
      // Bounded at 200 entries by default: a process cache disappears when the
      // app closes, a disk cache does not. Pass `maxEntries: null` to opt out.
      //
      // ⚠️ FileCacheStorage stores in CLEAR TEXT. Wrap it in
      // EncryptedCacheStorage (v4.0.0+) whenever what you keep between launches
      // is also what must not leak — amounts, personal data, anything about an
      // identified user. You supply the cipher, so apix holds no key.
      //
      // Note what is NOT sealed: the cache keys, because the invalidation API
      // reads them. An identifier in a path or query string stays readable on
      // disk — keep it out of URLs you cache.
      storage: EncryptedCacheStorage(
        delegate: FileCacheStorage(
          Directory('${cacheDir.path}/apix_cache'),
          maxEntries: 200,
        ),
        encrypt: appCipher.seal,
        decrypt: appCipher.open,
      ),
    ),
    // (v4.0.0+) Deduplication is independent of the cache: pass this WITHOUT a
    // cacheConfig when identical concurrent requests should collapse but
    // nothing may be stored.
    deduplicationConfig: const DeduplicationConfig(),
    // (v4.0.0+) One performance span per request, as a child of the current
    // Sentry transaction. apix already measured durations; this is what makes
    // them aggregatable instead of visible only after an incident.
    tracingConfig: const TracingConfig(),
    // Logger configuration (v1.0.1+)
    loggerConfig: const LoggerConfig(
      level: LogLevel.info,
      redactedHeaders: ['Authorization'],
    ),
    // Error tracking configuration (v1.0.1+)
    // Wired to the SentrySetup helpers initialised in [setupSentry] above.
    //
    // (v3.0.0+) `onError` receives the TYPED ApiException — ServerException,
    // NotFoundException, ConnectionException... — not the raw DioException.
    // Trackers group by runtime type, so this is what keeps a 500 and a 404
    // in separate issues. The DioException stays reachable through
    // `(exception as ApiException).originalError`.
    //
    // Only NetworkException (timeout, connection) is then filtered as
    // transport noise — ClientException and ServerException always reach
    // Sentry.
    errorTrackingConfig: const ErrorTrackingConfig(
      onError: SentrySetup.captureException,
      onBreadcrumb: SentrySetup.addBreadcrumbFromMap,
    ),
    // (v4.0.0+) Body key holding your API's application error code, surfaced
    // as `ApiException.code`. Defaults to 'code'; set it if your envelope
    // names the field differently (e.g. 'error_code').
    errorCodeKey: 'code',
    // Metrics configuration (v1.0.1+)
    metricsConfig: MetricsConfig(
      onMetrics: (metrics) {
        debugPrint(
            'API: ${metrics.method} ${metrics.path} - ${metrics.durationMs}ms');
      },
    ),
  );

  // ============================================================
  // TYPED RESPONSE METHODS (3 levels)
  // ============================================================

  try {
    // --- Level 1: Standard (raw Response) ---
    final response = await client.get<Map<String, dynamic>>('/users/1');
    // (v3.0.0+) Where the body came from, and whether it is past its TTL.
    // `isStale` is true when apix knowingly serves expired data: cacheFirst
    // revalidating behind, or an offline fallback. Surface it on anything
    // whose age changes what the user should do — an amount, a balance.
    if (response.isFromCache && response.isStale) {
      debugPrint('Showing data from earlier — refreshing…');
    }
    debugPrint('Raw: ${response.data}');

    // --- Level 2: Parse & Decode (formats response.data) ---
    // Decode: for JSON objects (tear-off friendly)
    final user = await client.getAndDecode('/users/1', User.fromJson);
    debugPrint('User: ${user.name}');

    // Parse: for any type (flexible)
    final count = await client.getAndParse(
      '/users/count',
      (data) => data as int,
    );
    debugPrint('Count: $count');

    // POST variants
    final created = await client.postAndDecode(
      '/users',
      {'name': 'John'},
      User.fromJson,
    );
    debugPrint('Created: ${created.name}');

    // (v2.3.0+) POST is not retried by default. Opt in per request with
    // forceRetry() when the call is safe to replay — e.g. protected by an
    // Idempotency-Key so the server collapses duplicates.
    final topup = await client.postAndDecode(
      '/wallet/topups',
      {'amount': 5000},
      User.fromJson,
      options: Options(
        headers: {'Idempotency-Key': 'a1b2c3d4'},
        extra: {forceRetryKey: true},
      ),
    );
    debugPrint('Top-up owner: ${topup.name}');

    // --- Level 3: Data Methods (envelope unwrapping) ---
    // For APIs returning: { "data": { ... } }
    // Extracts response.data[dataKey] then formats

    // Single object from envelope
    final profile = await client.getAndDecodeData('/profile', User.fromJson);
    debugPrint('Profile: ${profile.name}');

    // Nullable: returns null if data key is null
    final maybe =
        await client.getAndDecodeDataOrNull('/profile', User.fromJson);
    debugPrint('Maybe: ${maybe?.name}');

    // List from envelope: { "data": [{ ... }, { ... }] }
    final users = await client.getListAndDecodeData('/users', User.fromJson);
    debugPrint('Users: ${users.length}');

    // List with fallback to empty
    final empty =
        await client.getListAndDecodeDataOrEmpty('/users', User.fromJson);
    debugPrint('Users or empty: ${empty.length}');

    // Parse variant for non-JSON: { "data": ["admin", "editor"] }
    final roles = await client.getListAndParseData(
      '/roles',
      (item) => item as String,
    );
    debugPrint('Roles: $roles');

    // POST Data variants
    final searched = await client.postListAndDecodeData(
      '/search',
      {'query': 'john'},
      User.fromJson,
    );
    debugPrint('Search results: ${searched.length}');

    // --- Binary download (v4.0.0+) ---
    // `ResponseType` now comes from the apix barrel, so a PDF or an image no
    // longer forces a direct `package:dio` import — and with it, apix's dio
    // version range — into your code.
    final statement = await client.get<List<int>>(
      '/statements/2026-08.pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    debugPrint('Statement: ${statement.data?.length ?? 0} bytes');
  } on NotFoundException catch (e) {
    debugPrint('Not found: ${e.message}');
  } on UnauthorizedException catch (e) {
    // Includes AuthException (refresh failure) — see e.originalError for cause
    debugPrint('Auth error: ${e.message}');
  } on TooManyRequestsException catch (e) {
    // (v4.0.0+) Must be caught BEFORE ClientException — it is a subtype, so
    // the broader clause would swallow it and this branch would be dead code.
    //
    // `retryAfter` is null when the server sent no parseable Retry-After.
    // Null means "unknown delay", never "retry now".
    final wait = e.retryAfter;
    debugPrint(wait == null
        ? 'Trop de tentatives. Réessayez plus tard.'
        : 'Trop de tentatives. Réessayez dans ${wait.inSeconds} s.');
  } on ClientException catch (e) {
    // Any other 4xx (400, 409, 422...). The caller is at fault, so
    // retrying as-is won't help.
    //
    // (v4.0.0+) Prefer the application code over the status where your backend
    // publishes one: the same business case can drift from 400 to 409 to 422
    // across server revisions without changing meaning, and a call site keyed
    // on the status changes behaviour the day it does.
    switch (e.code) {
      case 'INSUFFICIENT_FUNDS':
        debugPrint('Solde insuffisant.');
      case 'OPERATION_NOT_RETRYABLE':
        debugPrint('Opération définitivement refusée.');
      case null:
        // No code in the body — fall back to the status.
        debugPrint('Client error ${e.statusCode}: ${e.message}');
      default:
        debugPrint('Erreur métier ${e.code}: ${e.message}');
    }
  } on ServerException catch (e) {
    // Any 5xx. Transient by nature: worth retrying and worth reporting.
    debugPrint('Server error ${e.statusCode}: ${e.message}');
  } on HttpException catch (e) {
    // Statuses outside 4xx/5xx that still reached the error path.
    debugPrint('HTTP ${e.statusCode}: ${e.message}');
  } on NetworkException catch (e) {
    debugPrint('Network: ${e.message}');
    // (v2.1.0+) Also fires on refresh-time network errors — no logout.
  } on TokenProviderException catch (e) {
    // (v2.1.0+) Keychain corrupted, custom TokenProvider threw, etc.
    debugPrint('Token storage failed (${e.operation.name}): ${e.message}');
  } on UnexpectedContentTypeException catch (e) {
    // (v2.1.0+) Only fires when strictContentType is enabled.
    debugPrint('Wrong Content-Type: expected ${e.expectedContentType}, '
        'got ${e.actualContentType ?? "(none)"}');
  } on ParsingException catch (e) {
    // (v2.1.0+) fromJson / parser threw — see e.originalError for cause.
    debugPrint('Parse failure: ${e.message}');
  } on ApiException catch (e) {
    debugPrint('API error: ${e.message}');
  }

  // Result pattern — functional error handling
  final result = await client.get<Map<String, dynamic>>('/users').getResult();
  result.when(
    success: (response) => debugPrint('Got ${response.data}'),
    failure: (error) => debugPrint('Error: ${error.message}'),
  );

  // ============================================================
  // TOKEN MANAGEMENT
  // ============================================================
  // After login, save tokens
  await tokenProvider.saveTokens('access_token_here', 'refresh_token_here');

  // Access underlying storage for other secrets
  await tokenProvider.storage.write('firebase_token', 'firebase_token_here');

  // On logout, clear tokens
  await tokenProvider.clearTokens();

  // Clean up
  client.close();
}

/// Example user model.
class User {
  final int id;
  final String name;
  final String email;

  User({required this.id, required this.name, required this.email});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }
}
