<p align="center">
  <img src="assets/logo_icon_filled.svg" alt="Apix Logo" width="120" height="120">
</p>

<h1 align="center">ApiX</h1>

<p align="center">
  <a href="https://pub.dev/packages/apix"><img src="https://img.shields.io/pub/v/apix.svg" alt="pub package"></a>
  <a href="https://github.com/Germinator97/apix/actions/workflows/ci.yaml"><img src="https://github.com/Germinator97/apix/actions/workflows/ci.yaml/badge.svg" alt="CI"></a>
  <a href="https://codecov.io/gh/Germinator97/apix"><img src="https://codecov.io/gh/Germinator97/apix/branch/develop/graph/badge.svg" alt="coverage"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
</p>

<p align="center">
  Production-ready Flutter/Dart API client with auth refresh queue, exponential retry, smart caching and error tracking (Sentry-ready). Powered by <a href="https://pub.dev/packages/dio">Dio</a>.
</p>

---

## Why ApiX?

Les développeurs Flutter passent un temps considérable à réimplémenter les mêmes patterns : refresh token, retry, cache, gestion d'erreurs. **ApiX** combine tout cela dans une solution clé-en-main.

| Problème | Solution ApiX |
|----------|---------------|
| Race conditions refresh token | **Refresh queue automatique** |
| Retry avec backoff manuel | **RetryInterceptor intégré** |
| Cache complexe à configurer | **Strategies prêtes à l'emploi** |
| Erreurs mal typées | **Hiérarchie d'exceptions granulaire** |

---

## Quick Start

```dart
import 'package:apix/apix.dart';

// Simple - fonctionne immédiatement
final client = ApiClientFactory.create(baseUrl: 'https://api.example.com');
final response = await client.get<Map<String, dynamic>>('/users');
```

**30 secondes** du `pub add` à la première requête.

---

## Installation

```yaml
dependencies:
  apix: ^1.0.0
```

```bash
flutter pub get
```

---

## Configuration Complète

ApiX supporte une configuration déclarative avec 6 paramètres optionnels :

```dart
final tokenProvider = SecureTokenProvider();

final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  
  // 🔐 Authentication avec refresh automatique
  authConfig: AuthConfig(
    tokenProvider: tokenProvider,
    refreshEndpoint: '/auth/refresh',
    onTokenRefreshed: (response) async {
      final data = response.data as Map<String, dynamic>;
      await tokenProvider.saveTokens(
        data['access_token'] as String,
        data['refresh_token'] as String,
      );
    },
  ),
  
  // 🔄 Retry avec exponential backoff
  retryConfig: const RetryConfig(
    maxAttempts: 3,
    retryStatusCodes: [500, 502, 503, 504],
  ),
  
  // 💾 Cache intelligent
  cacheConfig: CacheConfig(
    strategy: CacheStrategy.networkFirst,
    defaultTtl: const Duration(minutes: 5),
  ),
  
  // 📊 Logging configurable
  loggerConfig: const LoggerConfig(
    level: LogLevel.info,
    redactedHeaders: ['Authorization'],
  ),
  
  // 🐛 Error tracking (Sentry, Crashlytics, etc.)
  errorTrackingConfig: ErrorTrackingConfig(
    onError: (e, {stackTrace, extra, tags}) async {
      // Sentry
      await Sentry.captureException(e, stackTrace: stackTrace);

      // Firebase Crashlytics
      FirebaseCrashlytics.instance.recordError(e, stackTrace);

      // Custom / Debug
      debugPrint('Error: $e');
    },
  ),
  
  // 📈 Request metrics (Firebase, Amplitude, etc.)
  metricsConfig: const MetricsConfig(
    onMetrics: (metrics) {
      // Exemple avec votre service d'analytics
      debugPrint('${metrics.method} ${metrics.path} - ${metrics.durationMs}ms');
    },
  ),
);
```

---

## Features

### 🔐 Authentication & Secure Storage

```dart
// SecureTokenProvider utilise flutter_secure_storage
final tokenProvider = SecureTokenProvider();

final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  authConfig: AuthConfig(
    tokenProvider: tokenProvider,
    refreshEndpoint: '/auth/refresh',
    onTokenRefreshed: (response) async {
      final data = response.data as Map<String, dynamic>;
      await tokenProvider.saveTokens(
        data['access_token'] as String,
        data['refresh_token'] as String,
      );
    },
  ),
);

// Après login
await tokenProvider.saveTokens(accessToken, refreshToken);

// Logout
await tokenProvider.clearTokens();
```

**Refresh token queue** : Si plusieurs requêtes échouent avec 401, une seule refresh est lancée et toutes les requêtes attendent puis réessaient automatiquement.

---

### 🔄 Retry avec Exponential Backoff

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  retryConfig: const RetryConfig(
    maxAttempts: 3,
    retryStatusCodes: [500, 502, 503, 504],
    baseDelayMs: 1000,
    multiplier: 2.0,  // 1s → 2s → 4s
  ),
);

// Désactiver retry pour une requête spécifique
final response = await client.get<Map<String, dynamic>>(
  '/critical-endpoint',
  options: Options(extra: {noRetryKey: true}),
);
```

---

### 💾 Cache Intelligent

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  cacheConfig: CacheConfig(
    strategy: CacheStrategy.networkFirst,
    defaultTtl: const Duration(minutes: 5),
  ),
);

// Override par requête
final config = await client.get<Map<String, dynamic>>(
  '/app-config',
  options: Options(extra: {
    'cacheStrategy': CacheStrategy.cacheFirst,
    'cacheTtl': const Duration(hours: 24),
  }),
);

// Forcer refresh
final fresh = await client.get<Map<String, dynamic>>(
  '/users',
  options: Options(extra: {'forceRefresh': true}),
);
```

| Strategy | Comportement |
|----------|--------------|
| `cacheFirst` | Cache d'abord, network en background |
| `networkFirst` | Network d'abord, fallback cache |
| `cacheOnly` | Cache uniquement |
| `networkOnly` | Network uniquement |

---

### 📊 Logging

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  loggerConfig: const LoggerConfig(
    level: LogLevel.info,
    redactedHeaders: ['Authorization', 'Cookie'],
  ),
);
```

| Level | Description |
|-------|-------------|
| `none` | Aucun log |
| `error` | Erreurs uniquement |
| `warn` | Warnings + erreurs |
| `info` | Info + warnings + erreurs |
| `trace` | Tout (debug) |

---

### 🐛 Sentry Integration

**1. Initialisation Sentry (dans `main.dart`) :**

```dart
void main() async {
  await SentrySetup.init(
    options: SentrySetupOptions.production(
      dsn: 'https://xxx@xxx.ingest.sentry.io/xxx',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}

// Ou mode développement (pas de traces/replays)
await SentrySetup.init(
  options: SentrySetupOptions.development(
    dsn: 'your-sentry-dsn',
  ),
  appRunner: () => runApp(const MyApp()),
);
```

**2. Configuration du client API :**

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  errorTrackingConfig: ErrorTrackingConfig(
    onError: (e, {stackTrace, extra, tags}) async {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        withScope: (scope) {
          extra?.forEach((key, value) => scope.setExtra(key, value));
          tags?.forEach((key, value) => scope.setTag(key, value));
        },
      );
    },
    onBreadcrumb: (data) {
      Sentry.addBreadcrumb(Breadcrumb(
        message: data['message'] as String?,
        category: data['category'] as String?,
        data: data['data'] as Map<String, dynamic>?,
      ));
    },
  ),
);
```

| Option | Description |
|--------|-------------|
| `captureStatusCodes` | Status HTTP à capturer (défaut: 5xx) |
| `captureRequestBody` | Inclure le body request (défaut: false) |
| `captureResponseBody` | Inclure le body response (défaut: true) |
| `redactedHeaders` | Headers à masquer (Authorization, Cookie...) |

---

## Error Handling

### Hiérarchie d'exceptions

```
ApiException
├── NetworkException
│   ├── TimeoutException
│   └── ConnectionException
└── HttpException
    ├── ClientException (4xx)
    │   ├── UnauthorizedException (401)
    │   ├── ForbiddenException (403)
    │   └── NotFoundException (404)
    └── ServerException (5xx)
```

### Try-catch classique

```dart
try {
  final response = await client.get<Map<String, dynamic>>('/users');
} on NotFoundException catch (e) {
  print('User not found: ${e.message}');
} on UnauthorizedException catch (e) {
  print('Please login again');
} on NetworkException catch (e) {
  print('Check your connection: ${e.message}');
} on ApiException catch (e) {
  print('API error: ${e.message}');
}
```

### Result pattern (fonctionnel)

```dart
final result = await client.get<Map<String, dynamic>>('/users').getResult();

result.when(
  success: (response) => print('Got ${response.data}'),
  failure: (error) => print('Error: ${error.message}'),
);

// Ou avec pattern matching
if (result.isSuccess) {
  final data = result.valueOrNull;
}
```

---

## API Reference

### ApiClientFactory.create

| Paramètre | Type | Description |
|-----------|------|-------------|
| `baseUrl` | `String` | URL de base (required) |
| `connectTimeout` | `Duration` | Timeout connexion (30s) |
| `receiveTimeout` | `Duration` | Timeout réception (30s) |
| `headers` | `Map<String, dynamic>` | Headers par défaut |
| `authConfig` | `AuthConfig?` | Configuration auth |
| `retryConfig` | `RetryConfig?` | Configuration retry |
| `cacheConfig` | `CacheConfig?` | Configuration cache |
| `loggerConfig` | `LoggerConfig?` | Configuration logging |
| `errorTrackingConfig` | `ErrorTrackingConfig?` | Configuration error tracking |
| `metricsConfig` | `MetricsConfig?` | Configuration metrics |
| `interceptors` | `List<Interceptor>?` | Interceptors custom |

### Interceptors intégrés

| Interceptor | Ajouté via | Description |
|-------------|------------|-------------|
| `AuthInterceptor` | `authConfig` | Token injection + refresh queue |
| `RetryInterceptor` | `retryConfig` | Retry avec backoff |
| `CacheInterceptor` | `cacheConfig` | Cache multi-stratégies |
| `LoggerInterceptor` | `loggerConfig` | Logging request/response |
| `ErrorTrackingInterceptor` | `errorTrackingConfig` | Error tracking |
| `MetricsInterceptor` | `metricsConfig` | Request metrics |

---

## Example App

A complete Flutter app demonstrating all ApiX features is available on GitHub:

👉 **[apix_example_app](https://github.com/Germinator97/apix_example_app)**

<p align="center">
  <img src="assets/screenshots/home.png" alt="ApiX Example App" width="300">
</p>

Features demonstrated:
- 🔐 SecureTokenProvider with simplified refresh flow
- 💾 Cache strategies (CacheFirst, NetworkFirst, HttpCache)
- 🔄 Retry logic with exponential backoff
- 🐛 Sentry integration with error testing
- 📊 Request metrics and logging

## Contributing

Contributions are welcome! Please read our [contributing guidelines](CONTRIBUTING.md) first.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built on top of [Dio](https://pub.dev/packages/dio)
- Inspired by best practices from production Flutter apps

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/Germinator97">Germinator</a>
</p>
