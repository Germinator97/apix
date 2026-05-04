# Story 12.5: Add ProgressInterceptor for upload visibility in dev mode

Status: ready-for-dev

## Story

As a developer debugging large uploads,
I want a built-in `ProgressInterceptor` that logs upload/download progress at configurable thresholds,
so that I can see at a glance whether a slow request is making progress or stuck.

## Context (why)

Today, `onSendProgress`/`onReceiveProgress` are passed through to Dio (`api_client.dart:97`). Useful for production progress UIs — but during dev, devs end up writing the same throwaway `print` callback over and over to debug a stalled upload. ApiX should provide this out of the box, gated by `LoggerConfig`.

## Acceptance Criteria

1. **Given** `LoggerConfig(enabled: true)` and `ApiClientConfig(progressLogging: true)`
   **When** a request with body > a threshold is sent
   **Then** progress is logged at every 10% (configurable)
   **And** logs include URL, method, current/total bytes, and computed throughput (KB/s)

2. **Given** the same config
   **When** a response with non-trivial body is received
   **Then** download progress is logged at the same thresholds

3. **Given** `LoggerConfig(enabled: false)` OR `progressLogging: false`
   **Then** no progress logging happens (default — no overhead in production)

4. **Given** the user supplies their own `onSendProgress` callback
   **When** the request is sent
   **Then** **both** callbacks fire (the user's + the interceptor's logging)
   **And** order is documented (interceptor first, then user)

5. **Given** a request body smaller than `progressLoggingMinBytes` (default 64 KB)
   **Then** no progress logging (avoid noise on tiny payloads)

6. **Logging respects** `LoggerConfig.handler` (custom handler) and `LoggerConfig.level`

## Tasks / Subtasks

- [ ] Task 1: Add config to `LoggerConfig`
  - [ ] `bool progressLogging` (default `false`)
  - [ ] `int progressLoggingThresholdPercent` (default `10`)
  - [ ] `int progressLoggingMinBytes` (default `65536`)

- [ ] Task 2: Implement `ProgressInterceptor`
  - [ ] New file `lib/src/logging/progress_interceptor.dart`
  - [ ] Use `onRequest` to wrap `options.onSendProgress` chain (preserving any user-supplied callback)
  - [ ] Same for `onResponse` and `onReceiveProgress` (note: response progress is harder — Dio passes it via `Options`, may need a different hook)
  - [ ] Track previous logged percentage to throttle to threshold steps
  - [ ] Compute throughput: `bytes / elapsed`

- [ ] Task 3: Wire into `ApiClientFactory`
  - [ ] If `LoggerConfig.progressLogging` is `true`, register the interceptor
  - [ ] Order: after `LoggerInterceptor` (so the latter still logs request start)

- [ ] Task 4: Unit tests
  - [ ] Disabled by default → no logs (regression)
  - [ ] 1 MB upload → logs at 10%, 20%, … 100%
  - [ ] User-supplied callback → both fire, in correct order
  - [ ] Body < `progressLoggingMinBytes` → no logs
  - [ ] Custom threshold (e.g. 25%) honored
  - [ ] Throughput calculation reasonable on mocked timestamps

- [ ] Task 5: Documentation
  - [ ] README mention under "Logging & observability"
  - [ ] Note that this is **dev-only** — production should use `MetricsInterceptor`

## Dev Notes

### Implementation challenges

- **Wrapping `onSendProgress`**: `Dio` accepts a single callback per request. Solution: wrap the user's callback in our own that calls both, and inject via `Options` munging in `onRequest`.
- **Callback ordering on retries**: when `RetryInterceptor` replays a request, it re-uses the wrapped callback. That's correct (both callbacks still fire) but the throughput counter resets — document this.

### Implementation pattern

```dart
class ProgressInterceptor extends Interceptor {
  final LoggerConfig config;

  ProgressInterceptor(this.config);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!config.enabled || !config.progressLogging) {
      handler.next(options);
      return;
    }
    final userCallback = options.onSendProgress;
    int? lastLogged;
    final start = DateTime.now();
    options.onSendProgress = (sent, total) {
      userCallback?.call(sent, total);
      if (total < config.progressLoggingMinBytes) return;
      final pct = (sent * 100 / total).round();
      final step = config.progressLoggingThresholdPercent;
      final bucket = pct ~/ step * step;
      if (lastLogged == bucket) return;
      lastLogged = bucket;
      final elapsed = DateTime.now().difference(start).inMilliseconds.clamp(1, 1<<30);
      final kbps = (sent / elapsed).toStringAsFixed(1);
      config.handler('[apix] ${options.method} ${options.uri}: '
          '$bucket% ($sent/$total bytes, $kbps KB/s)');
    };
    handler.next(options);
  }
}
```

### References

- `lib/src/client/api_client.dart:97` — current `onSendProgress` passthrough
- `lib/src/logging/logger_config.dart`

## Dev Agent Record

### File List (Target)

- `lib/src/logging/progress_interceptor.dart` — new
- `lib/src/logging/logger_config.dart` — extend
- `lib/src/client/api_client_factory.dart` — wire
- `lib/apix.dart` — export
- `test/logging/progress_interceptor_test.dart` — new
