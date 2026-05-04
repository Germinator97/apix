/// Apix Example
///
/// This example demonstrates the basic usage of the apix package,
/// including SecureTokenProvider for secure token storage.
library;

import 'package:apix/apix.dart';
import 'package:flutter/material.dart';

/// Simple example showing API client creation and usage.
void main() async {
  // ============================================================
  // SECURE TOKEN STORAGE
  // ============================================================
  // SecureTokenProvider uses flutter_secure_storage under the hood
  final tokenProvider = SecureTokenProvider();

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
    ),
    // Cache configuration (v1.0.1+)
    cacheConfig: CacheConfig(
      strategy: CacheStrategy.networkFirst,
      defaultTtl: const Duration(minutes: 5),
    ),
    // Logger configuration (v1.0.1+)
    loggerConfig: const LoggerConfig(
      level: LogLevel.info,
      redactedHeaders: ['Authorization'],
    ),
    // Error tracking configuration (v1.0.1+)
    errorTrackingConfig: ErrorTrackingConfig(
      onError: (Object e,
          {StackTrace? stackTrace,
          Map<String, dynamic>? extra,
          Map<String, String>? tags}) async {
        debugPrint('Error captured: $e');
      },
    ),
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
  } on NotFoundException catch (e) {
    debugPrint('Not found: ${e.message}');
  } on UnauthorizedException catch (e) {
    // Includes AuthException (refresh failure) — see e.originalError for cause
    debugPrint('Auth error: ${e.message}');
  } on HttpException catch (e) {
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
