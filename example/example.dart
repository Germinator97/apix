/// Apix Example
///
/// This example demonstrates the basic usage of the apix package,
/// including SecureTokenProvider for secure token storage.
library;

import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
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
      // Called when refresh fails — clear tokens and redirect to login
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
  } on DioException catch (e) {
    // Errors from Dio are wrapped — extract the typed ApiException
    final apiError = e.error;
    if (apiError is NotFoundException) {
      debugPrint('Not found: ${apiError.message}');
    } else if (apiError is UnauthorizedException) {
      debugPrint('Auth error: ${apiError.message}');
    } else if (apiError is NetworkException) {
      debugPrint('Network error: ${apiError.message}');
    } else {
      debugPrint('Error: $apiError');
    }
  }

  // Result pattern — the recommended approach (handles DioException internally)
  final result = await client.get<Map<String, dynamic>>('/users').getResult();
  result.when(
    success: (response) => debugPrint('Got ${response.data}'),
    failure: (error) {
      // error is already a typed ApiException — no DioException wrapper
      if (error is UnauthorizedException) {
        debugPrint('Auth: ${error.message}');
      } else {
        debugPrint('Error: ${error.message}');
      }
    },
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
