# Apix

[![pub package](https://img.shields.io/pub/v/apix.svg)](https://pub.dev/packages/apix)
[![CI](https://github.com/Germinator97/apix/actions/workflows/ci.yml/badge.svg)](https://github.com/Germinator97/apix/actions/workflows/ci.yml)
[![coverage](https://codecov.io/gh/Germinator97/apix/branch/main/graph/badge.svg)](https://codecov.io/gh/Germinator97/apix)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Production-ready Flutter/Dart API client with auth refresh queue, exponential retry, smart caching, and built-in Sentry integration. Powered by [Dio](https://pub.dev/packages/dio).

## Quick Start

```dart
import 'package:apix/apix.dart';

final client = ApiClientFactory.create(baseUrl: 'https://api.example.com');
final response = await client.get('/users');
```

**That's it!** You have a fully configured API client with sensible defaults.

## Features

| Feature | Description |
|---------|-------------|
| 🔐 **Auth Refresh Queue** | Automatic token refresh with request queuing |
| 🔄 **Retry Logic** | Exponential backoff with jitter |
| 💾 **Smart Caching** | CacheFirst, NetworkFirst, HttpCacheAware strategies |
| 📊 **Logging** | Configurable request/response logging |
| 🐛 **Sentry Integration** | Built-in error tracking and breadcrumbs |
| 📈 **Metrics** | Request timing and performance tracking |

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  apix: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## Usage

### Basic Client

```dart
import 'package:apix/apix.dart';

// Create a simple client
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
);

// GET request
final users = await client.get('/users');

// POST request
final newUser = await client.post('/users', data: {
  'name': 'John Doe',
  'email': 'john@example.com',
});
```

### With Authentication

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  authConfig: AuthConfig(
    tokenProvider: TokenProvider(
      getAccessToken: () async => secureStorage.read('access_token'),
      getRefreshToken: () async => secureStorage.read('refresh_token'),
      saveTokens: (access, refresh) async {
        await secureStorage.write('access_token', access);
        await secureStorage.write('refresh_token', refresh);
      },
      clearTokens: () async => secureStorage.deleteAll(),
    ),
    refreshEndpoint: '/auth/refresh',
  ),
);
```

### With Retry

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  retryConfig: RetryConfig(
    maxRetries: 3,
    retryableStatusCodes: {408, 429, 500, 502, 503, 504},
    initialDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 30),
  ),
);

// Disable retry for specific request
final response = await client.get(
  '/critical-endpoint',
  options: Options(extra: {'noRetry': true}),
);
```

### With Caching

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  cacheConfig: CacheConfig(
    defaultStrategy: CacheStrategy.networkFirst,
    defaultTtl: Duration(minutes: 5),
  ),
);

// Use cache-first for static data
final config = await client.get(
  '/app-config',
  options: Options(extra: {
    'cacheStrategy': CacheStrategy.cacheFirst,
    'cacheTtl': Duration(hours: 24),
  }),
);

// Force refresh
final freshData = await client.get(
  '/users',
  options: Options(extra: {'forceRefresh': true}),
);
```

### With Logging

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  loggerConfig: LoggerConfig(
    level: LogLevel.info,
    logRequestHeaders: true,
    logResponseBody: true,
    redactedHeaders: ['Authorization', 'Cookie'],
  ),
);
```

### With Sentry

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

void main() async {
  // Optional: ensures Flutter errors are captured before runApp
  SentryWidgetsFlutterBinding.ensureInitialized();

  await SentrySetup.init(
    options: SentrySetupOptions(
      dsn: 'your-sentry-dsn',
      environment: 'production',
    ),
    appRunner: () async {
      runApp(const MyApp());
    },
  );
}

// In your app
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
);

// Add Sentry interceptor
client.interceptors.add(SentryInterceptor(
  config: SentryConfig(
    environment: 'production',
    captureException: (e, {stackTrace, extra, tags}) async {
      await Sentry.captureException(e, stackTrace: stackTrace);
    },
    addBreadcrumb: (data) {
      Sentry.addBreadcrumb(Breadcrumb(
        message: data['message'] as String?,
        category: data['category'] as String?,
        data: data['data'] as Map<String, dynamic>?,
      ));
    },
  ),
));
```

### With Metrics

```dart
client.interceptors.add(MetricsInterceptor(
  config: MetricsConfig(
    onMetrics: (metrics) {
      analytics.track('api_request', {
        'method': metrics.method,
        'path': metrics.path,
        'duration_ms': metrics.durationMs,
        'status_code': metrics.statusCode,
        'success': metrics.success,
      });
    },
    onBreadcrumb: (breadcrumb) {
      // Track navigation breadcrumbs
    },
  ),
));
```

### Full Configuration

```dart
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  config: ApiClientConfig(
    connectTimeout: Duration(seconds: 30),
    receiveTimeout: Duration(seconds: 30),
    defaultHeaders: {
      'X-App-Version': '1.0.0',
      'X-Platform': Platform.operatingSystem,
    },
  ),
  authConfig: AuthConfig(...),
  retryConfig: RetryConfig(...),
  cacheConfig: CacheConfig(...),
  loggerConfig: LoggerConfig(...),
);
```

## Result Type

Apix provides a `Result<T>` type for safe error handling:

```dart
final result = await client.getResult<User>('/users/1');

result.when(
  success: (user) => print('Got user: ${user.name}'),
  failure: (error) => print('Error: ${error.message}'),
);

// Or use pattern matching
if (result.isSuccess) {
  final user = result.data;
}
```

## Error Handling

```dart
try {
  final response = await client.get('/users');
} on HttpException catch (e) {
  print('HTTP ${e.statusCode}: ${e.message}');
} on NetworkException catch (e) {
  print('Network error: ${e.message}');
} on ApiException catch (e) {
  print('API error: ${e.message}');
}
```

## API Reference

### Interceptors

| Interceptor | Description |
|-------------|-------------|
| `AuthInterceptor` | Handles token injection and refresh |
| `RetryInterceptor` | Retries failed requests with backoff |
| `CacheInterceptor` | Caches responses with configurable strategies |
| `LoggerInterceptor` | Logs requests and responses |
| `SentryInterceptor` | Captures errors and breadcrumbs |
| `MetricsInterceptor` | Tracks request metrics |

### Cache Strategies

| Strategy | Description |
|----------|-------------|
| `CacheStrategy.cacheFirst` | Return cache, fetch in background |
| `CacheStrategy.networkFirst` | Try network, fallback to cache |
| `CacheStrategy.httpCacheAware` | Respect HTTP cache headers |

### Log Levels

| Level | Description |
|-------|-------------|
| `LogLevel.none` | No logging |
| `LogLevel.error` | Errors only |
| `LogLevel.warn` | Warnings and errors |
| `LogLevel.info` | Info, warnings, errors |
| `LogLevel.trace` | Everything |

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
