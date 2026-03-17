// Apix - Production-ready Flutter/Dart API client.
//
// Features:
// - Auth refresh queue with automatic token management
// - Exponential retry with configurable backoff
// - Smart caching (CacheFirst, NetworkFirst, HttpCacheAware)
// - Built-in Sentry integration

// Auth
export 'src/auth/auth_config.dart';
export 'src/auth/auth_interceptor.dart';
export 'src/auth/token_provider.dart';

// Client
export 'src/client/api_client.dart';
export 'src/client/api_client_config.dart';
export 'src/client/api_client_factory.dart';
export 'src/client/multipart_interceptor.dart';

// Errors
export 'src/errors/api_exception.dart';
export 'src/errors/http_exception.dart';
export 'src/errors/network_exception.dart';

// Models
export 'src/models/result.dart';

// Retry
export 'src/retry/retry_config.dart';
export 'src/retry/retry_interceptor.dart';
