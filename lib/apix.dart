// Apix - Production-ready Flutter/Dart API client.
//
// Features:
// - Auth refresh queue with automatic token management
// - Exponential retry with configurable backoff
// - Smart caching (CacheFirst, NetworkFirst, HttpCacheAware)
// - Logging with configurable levels
// - Error tracking with Sentry integration
// - Request metrics and breadcrumbs

// Auth
export 'src/auth/auth_config.dart';
export 'src/auth/auth_interceptor.dart';
export 'src/auth/secure_storage_service.dart';
export 'src/auth/secure_token_provider.dart';
export 'src/auth/token_provider.dart';
export 'src/auth/token_provider_exception.dart';

// Client
export 'src/client/api_client.dart';
export 'src/client/api_client_config.dart';
export 'src/client/api_client_factory.dart';
export 'src/client/multipart_interceptor.dart';
export 'src/client/response_validator_interceptor.dart';

// Errors
export 'src/errors/api_exception.dart';
export 'src/errors/error_mapper_interceptor.dart';
export 'src/errors/http_exception.dart';
export 'src/errors/network_exception.dart';
export 'src/errors/parsing_exception.dart';
export 'src/errors/unexpected_content_type_exception.dart';

// Models
export 'src/models/result.dart';

// Retry
export 'src/retry/retry_config.dart';
export 'src/retry/retry_interceptor.dart';

// Cache
export 'src/cache/cache_config.dart';
export 'src/cache/cache_entry.dart';
export 'src/cache/cache_interceptor.dart';
export 'src/cache/cache_storage.dart';
export 'src/cache/deduplication_config.dart';
export 'src/cache/deduplication_interceptor.dart';
export 'src/cache/file_cache_storage.dart';
export 'src/cache/request_deduplicator.dart';

// Logging
export 'src/logging/logger_config.dart';
export 'src/logging/logger_interceptor.dart';

// Observability
export 'src/observability/error_tracking_interceptor.dart';
export 'src/observability/metrics_interceptor.dart';
export 'src/observability/sentry_setup.dart';

// Dio re-exports
//
// Types surfaced by apix's public API (e.g. `client.get(options: ...)` returns
// `Response<T>`, `Options(extra: {noRetryKey: true})`, `cancelToken:`) so
// consumers don't need a direct `package:dio` import for common calls.
export 'package:dio/dio.dart' show CancelToken, Options, Response;
