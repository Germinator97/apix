import 'package:dio/dio.dart';

import 'deduplication_config.dart';
import 'request_deduplicator.dart';

/// Interceptor that collapses identical concurrent requests into one call,
/// without storing anything.
///
/// Install it when you want deduplication but no cache. When a `CacheConfig`
/// is also in play, `CacheInterceptor` already deduplicates on its own —
/// running both would deduplicate twice, so `ApiClientFactory` disables the
/// cache's own deduplication whenever this interceptor is wired in.
///
/// Example:
/// ```dart
/// final dio = Dio();
/// final dedup = DeduplicationInterceptor(config: const DeduplicationConfig());
/// dedup.setDio(dio);
/// dio.interceptors.add(dedup);
/// ```
class DeduplicationInterceptor extends Interceptor {
  /// The deduplication configuration.
  final DeduplicationConfig config;

  final RequestDeduplicator _deduplicator = RequestDeduplicator();

  /// Dio instance used to execute the single real request.
  Dio? _dio;

  /// Creates a [DeduplicationInterceptor] with the given [config].
  DeduplicationInterceptor({required this.config});

  /// Sets the Dio instance used to execute deduplicated requests.
  ///
  /// Must be called after adding this interceptor to Dio. Without it the
  /// interceptor passes every request straight through rather than failing:
  /// losing deduplication is a performance regression, blocking the request
  /// would be an outage.
  void setDio(Dio dio) {
    _dio = dio;
  }

  /// Returns the request deduplicator (for testing).
  RequestDeduplicator get deduplicator => _deduplicator;

  /// Key used in [RequestOptions.extra] to bypass this interceptor on re-entry.
  static const String _skipKey = '_apix_skip_dedup';

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // The single real request re-enters the chain; it must not be deduplicated
    // against itself.
    if (options.extra[_skipKey] == true ||
        _dio == null ||
        !config.shouldDeduplicate(options.method)) {
      handler.next(options);
      return;
    }

    try {
      final response = await _deduplicator.deduplicate(
        options,
        () => _dio!.fetch<dynamic>(options.copyWith(
          extra: {...options.extra, _skipKey: true},
        )),
      );
      handler.resolve(response);
    } on DioException catch (e) {
      // Every waiter on a collapsed request gets the same failure — which is
      // the point: they would each have got it separately anyway.
      handler.reject(e);
    } catch (e) {
      // A non-Dio failure would otherwise escape as an unhandled async error
      // with no request attached to it.
      handler.reject(
        DioException(requestOptions: options, error: e),
      );
    }
  }
}
