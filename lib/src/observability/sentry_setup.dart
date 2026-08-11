import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../errors/api_exception.dart';
import '../errors/network_exception.dart';

/// Configuration options for Sentry initialization.
class SentrySetupOptions {
  /// Sentry DSN (Data Source Name).
  final String dsn;

  /// Environment name (e.g., 'production', 'staging', 'development').
  final String environment;

  /// Whether Sentry is enabled.
  final bool enabled;

  /// Sample rate for error events (0.0 to 1.0).
  final double sampleRate;

  /// Sample rate for performance traces (0.0 to 1.0).
  final double tracesSampleRate;

  /// Sample rate for profiling (0.0 to 1.0).
  final double profilesSampleRate;

  /// Sample rate for error replays (0.0 to 1.0).
  final double replayOnErrorSampleRate;

  /// Sample rate for session replays (0.0 to 1.0).
  final double replaySessionSampleRate;

  /// Whether to send default PII (Personally Identifiable Information).
  ///
  /// **Defaults to `false`**, matching Sentry's own default. It used to default
  /// to `true`, so every app wiring `SentrySetup` shipped request headers,
  /// cookies and IP addresses to the tracker unless it thought to say
  /// otherwise — a choice worth making deliberately, in a package whose users
  /// are often working on financial data, and one that a privacy policy has to
  /// be able to describe truthfully.
  ///
  /// Set it to `true` when you have decided you want that, and said so where
  /// your users can read it.
  final bool sendDefaultPii;

  /// Whether to capture failed HTTP requests.
  final bool captureFailedRequests;

  /// Whether to enable ANR (Application Not Responding) detection.
  final bool anrEnabled;

  /// Whether to filter network noise errors.
  final bool filterNetworkNoise;

  /// Minimum transaction duration in milliseconds to report.
  final int minTransactionDurationMs;

  /// Custom beforeSend callback.
  final FutureOr<SentryEvent?> Function(SentryEvent event, Hint hint)?
      customBeforeSend;

  /// Custom beforeSendTransaction callback.
  final FutureOr<SentryTransaction?> Function(
    SentryTransaction transaction,
    Hint hint,
  )? customBeforeSendTransaction;

  /// Escape hatch for tuning [SentryFlutterOptions] not exposed by apix.
  ///
  /// Invoked **last**, after every apix default — so it can override anything,
  /// including `beforeSend` / `beforeSendTransaction`. For composition that
  /// preserves apix's network-noise filter, prefer [customBeforeSend] /
  /// [customBeforeSendTransaction] instead.
  ///
  /// Typical use: enable Sentry options introduced in newer SDK versions
  /// without waiting for an apix release (e.g. `enableTombstone`,
  /// `enableAppHangTrackingV2`, replay tuning).
  ///
  /// Exceptions thrown here are swallowed in release builds and rethrown in
  /// debug, to avoid breaking app startup on a typo.
  final void Function(SentryFlutterOptions options)? configureOptions;

  const SentrySetupOptions({
    required this.dsn,
    required this.environment,
    this.enabled = true,
    this.sampleRate = 1.0,
    this.tracesSampleRate = 0.5,
    this.profilesSampleRate = 0.1,
    this.replayOnErrorSampleRate = 1.0,
    this.replaySessionSampleRate = 0.1,
    this.sendDefaultPii = false,
    this.captureFailedRequests = true,
    this.anrEnabled = false,
    this.filterNetworkNoise = true,
    this.minTransactionDurationMs = 100,
    this.customBeforeSend,
    this.customBeforeSendTransaction,
    this.configureOptions,
  });

  /// Creates options for production environment.
  factory SentrySetupOptions.production({
    required String dsn,
    String environment = 'production',
  }) =>
      SentrySetupOptions(
        dsn: dsn,
        environment: environment,
        tracesSampleRate: 0.5,
        profilesSampleRate: 0.1,
        replayOnErrorSampleRate: 1.0,
        replaySessionSampleRate: 0.1,
      );

  /// Creates options for development/debug environment.
  factory SentrySetupOptions.development({
    required String dsn,
    String environment = 'development',
  }) =>
      SentrySetupOptions(
        dsn: dsn,
        environment: environment,
        tracesSampleRate: 0.0,
        profilesSampleRate: 0.0,
        replayOnErrorSampleRate: 0.0,
        replaySessionSampleRate: 0.0,
      );
}

/// Sentry setup and initialization helper.
///
/// Example:
/// ```dart
/// void main() async {
///   await SentrySetup.init(
///     options: SentrySetupOptions(
///       dsn: 'your-sentry-dsn',
///       environment: 'production',
///     ),
///     appRunner: () async {
///       runApp(const MyApp());
///     },
///   );
/// }
/// ```
class SentrySetup {
  SentrySetup._();

  static bool _isInitialized = false;

  /// Whether Sentry has been initialized.
  static bool get isInitialized => _isInitialized;

  /// Initializes Sentry with the given options.
  ///
  /// **The app starts even if this fails.** `SentryFlutter.init` runs
  /// [appRunner] itself, so anything that threw before it got there — a
  /// malformed DSN, a plugin missing on a platform, a `configureOptions`
  /// touching an option the installed SDK no longer has — took the whole app
  /// down with it. Crash reporting is a side channel; a side channel that can
  /// prevent startup is a worse liability than the reports it collects.
  static Future<void> init({
    required SentrySetupOptions options,
    required Future<void> Function() appRunner,
  }) async {
    if (!options.enabled) {
      await appRunner();
      return;
    }

    if (_isInitialized) {
      await appRunner();
      return;
    }

    await guardedStart(
      appRunner: appRunner,
      initialize: (runner) => _initialize(options, runner),
    );
  }

  /// Runs [initialize], and guarantees the app starts exactly once.
  ///
  /// Split out so the failure path is reachable from a test: exercising it
  /// through `SentryFlutter.init` would need a live platform channel, which is
  /// how it came to have none.
  ///
  /// Two things have to hold together, and each is easy to get right while
  /// breaking the other: the app must start even when initialization throws,
  /// and it must not start **twice** — `SentryFlutter.init` may well have run
  /// the runner already before failing on something after it.
  @visibleForTesting
  static Future<void> guardedStart({
    required Future<void> Function() appRunner,
    required Future<void> Function(Future<void> Function() runner) initialize,
  }) async {
    var started = false;
    Future<void> runOnce() async {
      if (started) return;
      started = true;
      await appRunner();
    }

    try {
      await initialize(runOnce);
      _isInitialized = true;
    } catch (e, st) {
      // Never rethrown: there is no caller above `main` to handle it, and the
      // one thing worse than an app with no crash reporting is no app.
      debugPrint('⚠️ [Sentry] init failed, continuing without it: $e\n$st');
    }

    // The flag stays false on failure, so a later, legitimate retry is not
    // silently skipped — the same reason it is only set once init returns.
    await runOnce();
  }

  static Future<void> _initialize(
    SentrySetupOptions options,
    Future<void> Function() appRunner,
  ) async {
    await SentryFlutter.init(
      (sentryOptions) {
        sentryOptions.dsn = options.dsn;
        sentryOptions.environment = options.environment;

        sentryOptions.sendDefaultPii = options.sendDefaultPii;
        sentryOptions.sampleRate = options.sampleRate;

        // Disable tracing in debug mode
        sentryOptions.tracesSampleRate =
            kDebugMode ? 0.0 : options.tracesSampleRate;

        // Profiling and replay are now actually wired.
        //
        // These three were accepted by `SentrySetupOptions`, documented, and
        // set by both of its factories — while the lines that applied them sat
        // commented out behind "available in newer versions". That note was
        // stale: the pubspec requires sentry_flutter >=9.0.0, which exposes
        // `profilesSampleRate` and `replay.*`. So
        // `SentrySetupOptions.production()` configured three things that did
        // nothing, and nothing anywhere said so — the worst kind of option,
        // one that looks set.
        sentryOptions.profilesSampleRate =
            kDebugMode ? 0.0 : options.profilesSampleRate;
        sentryOptions.replay.onErrorSampleRate =
            kDebugMode ? 0.0 : options.replayOnErrorSampleRate;
        sentryOptions.replay.sessionSampleRate =
            kDebugMode ? 0.0 : options.replaySessionSampleRate;

        sentryOptions.debug = kDebugMode;
        sentryOptions.captureFailedRequests = options.captureFailedRequests;
        sentryOptions.anrEnabled = options.anrEnabled;

        // Session and performance tracking
        sentryOptions.enableAutoSessionTracking = true;
        sentryOptions.enableAutoPerformanceTracing = true;

        // Event filtering
        sentryOptions.beforeSend = (event, hint) => _beforeSend(
              event,
              hint,
              options,
            );

        sentryOptions.beforeSendTransaction =
            (transaction, hint) => _beforeSendTransaction(
                  transaction,
                  hint,
                  options,
                );

        // Escape hatch: invoked last so consumers can override any option.
        // Guarded to avoid crashing app startup on a faulty callback.
        if (options.configureOptions != null) {
          try {
            options.configureOptions!(sentryOptions);
          } catch (e, st) {
            debugPrint('⚠️ [Sentry] configureOptions threw: $e\n$st');
            if (kDebugMode) rethrow;
          }
        }
      },
      appRunner: appRunner,
    );
  }

  /// Resets the one-shot guard. Test-only.
  ///
  /// `init` is idempotent by design, which makes it impossible to exercise
  /// twice in a suite without this.
  @visibleForTesting
  static void resetForTesting() {
    _isInitialized = false;
  }

  /// Decides whether [event] is sent. Exposed for testing.
  ///
  /// This is a component whose entire job is to **drop** events, wired into
  /// the channel that would otherwise report its own mistakes. Over-filtering
  /// here produces an absence, and an absence looks exactly like a quiet day —
  /// which is how `isNetworkNoiseError` came to discard every server error
  /// ApiX reported without anyone noticing. It has to be exercised directly.
  @visibleForTesting
  static FutureOr<SentryEvent?> beforeSendForTesting(
    SentryEvent event,
    Hint hint,
    SentrySetupOptions options,
  ) =>
      _beforeSend(event, hint, options);

  /// Whether a transaction running from [start] to [end] is too short to be
  /// worth reporting, per [SentrySetupOptions.minTransactionDurationMs].
  ///
  /// Extracted so the rule can be tested without building a real
  /// `SentryTransaction`, which needs an `@internal` `SentryTracer` — importing
  /// sentry's internals from a test would couple this suite to a private shape
  /// across the whole declared `>=9.0.0 <10.0.0` range, and turn a CI red
  /// without a line of apix changing.
  ///
  /// A null [end] means the transaction has no measurable duration, which is
  /// not a reason to drop it.
  @visibleForTesting
  static bool isTooShort(DateTime start, DateTime? end, int minDurationMs) {
    if (end == null) return false;
    return end.difference(start).inMilliseconds < minDurationMs;
  }

  static FutureOr<SentryEvent?> _beforeSend(
    SentryEvent event,
    Hint hint,
    SentrySetupOptions options,
  ) {
    // Filter network noise
    if (options.filterNetworkNoise && isNetworkNoiseError(event)) {
      return null;
    }

    // Call custom beforeSend if provided
    if (options.customBeforeSend != null) {
      return options.customBeforeSend!(event, hint);
    }

    // Log in development environment
    if (options.environment == 'development') {
      final exception = event.exceptions?.firstOrNull;
      debugPrint(
        '🚨 [Sentry] Event sent: ${exception?.type ?? event.eventId}',
      );
    }

    return event;
  }

  static FutureOr<SentryTransaction?> _beforeSendTransaction(
    SentryTransaction transaction,
    Hint hint,
    SentrySetupOptions options,
  ) {
    // Filter short transactions. The rule lives in [isTooShort] so it can be
    // exercised without constructing a SentryTransaction.
    if (isTooShort(
      transaction.startTimestamp,
      transaction.timestamp,
      options.minTransactionDurationMs,
    )) {
      return null;
    }

    // Call custom beforeSendTransaction if provided.
    //
    // Forwarding the real hint, not a fresh one: this used to build `Hint()`
    // on the spot, so every attachment and every piece of context Sentry had
    // gathered for the transaction was dropped before the consumer's callback
    // ever saw it — and a callback reading an empty hint looks exactly like one
    // reading a hint that happens to be empty.
    if (options.customBeforeSendTransaction != null) {
      return options.customBeforeSendTransaction!(transaction, hint);
    }

    return transaction;
  }

  /// Checks if an event is a network noise error that should be filtered.
  ///
  /// ApiX's own exceptions are classified from the **type hierarchy**, never
  /// from the type name: `SentryException.type` is
  /// `throwable.runtimeType.toString()`, i.e. a bare class name with no
  /// package qualifier, so `HttpException`, `ClientException` and
  /// `TimeoutException` are indistinguishable by name from their `dart:io` /
  /// `dart:async` namesakes. Name matching alone silently discarded every
  /// server error ApiX reported.
  ///
  /// Everything else keeps the name-based matching below, so a genuine
  /// `dart:async` `TimeoutException` or `dart:io` `HttpException` is still
  /// filtered as before.
  static bool isNetworkNoiseError(SentryEvent event) {
    final exceptions = event.exceptions ?? [];

    for (final exception in exceptions) {
      final throwable = exception.throwable;

      // When the original object is available, the hierarchy is authoritative
      // and no string is consulted: an ApiX NetworkException is transport
      // noise, any other ApiException is a real error worth reporting.
      if (throwable is ApiException) {
        if (throwable is NetworkException) return true;
        continue;
      }

      final type = exception.type ?? '';
      final value = exception.value ?? '';

      // Filter by exception type
      if (_isNetworkExceptionType(type)) {
        return true;
      }

      // Filter by error message
      if (_isNetworkErrorMessage(value)) {
        return true;
      }
    }

    return false;
  }

  static bool _isNetworkExceptionType(String type) {
    // Reached only for non-ApiX throwables (and for events with no throwable
    // at all), so matching by name is both safe and necessary here: a real
    // `dart:async` TimeoutException or a `dart:io` HttpException must still
    // be filtered. ApiX's own types never reach this point — they are settled
    // by the hierarchy in [isNetworkNoiseError].
    const networkExceptionPrefixes = [
      'SocketException',
      'HandshakeException',
      'TlsException',
    ];

    const dartOnlyTypes = [
      'ClientException',
      'TimeoutException',
      'HttpException',
    ];

    if (networkExceptionPrefixes.any((t) => type.contains(t))) {
      return true;
    }

    // Both spellings are matched on purpose.
    //
    // For a Dart throwable, `SentryException.type` is `runtimeType.toString()`
    // — a bare class name with no library prefix — which made the qualified
    // form look like dead code. It is not guaranteed to be: an event can also
    // arrive from a native integration or be constructed directly, and nothing
    // in the SDK promises the bare form for those. A test pins the qualified
    // case, and removing the clause is a behaviour change that buys nothing.
    for (final t in dartOnlyTypes) {
      if (type == t || (type.startsWith('dart:') && type.contains(t))) {
        return true;
      }
    }

    return false;
  }

  static bool _isNetworkErrorMessage(String message) {
    const networkErrorMessages = [
      'Connection refused',
      'Connection reset',
      'Connection closed',
      'No route to host',
      'Network is unreachable',
      'Connection timed out',
      'Software caused connection abort',
      'Broken pipe',
      'Host not found',
      'DNS lookup failed',
    ];

    return networkErrorMessages.any((m) => message.contains(m));
  }

  /// Returns a Sentry navigator observer for tracking navigation.
  static SentryNavigatorObserver get navigatorObserver =>
      SentryNavigatorObserver();

  /// Captures an exception to Sentry.
  static Future<void> captureException(
    dynamic exception, {
    StackTrace? stackTrace,
    Map<String, dynamic>? extra,
    Map<String, String>? tags,
  }) async {
    await Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      withScope: (scope) {
        extra?.forEach((key, value) => scope.setContexts(key, value));
        tags?.forEach((key, value) => scope.setTag(key, value));
      },
    );
  }

  /// Adds a breadcrumb to the current scope.
  static void addBreadcrumb({
    required String message,
    String? category,
    Map<String, dynamic>? data,
    SentryLevel level = SentryLevel.info,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        data: data,
        level: level,
      ),
    );
  }

  /// Adds a breadcrumb from a map (for use with ErrorTrackingConfig.onBreadcrumb).
  ///
  /// Example:
  /// ```dart
  /// errorTrackingConfig: ErrorTrackingConfig(
  ///   onError: SentrySetup.captureException,
  ///   onBreadcrumb: SentrySetup.addBreadcrumbFromMap,
  /// ),
  /// ```
  static void addBreadcrumbFromMap(Map<String, dynamic> data) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: data['message'] as String?,
        category: data['category'] as String?,
        data: data['data'] as Map<String, dynamic>?,
        level: SentryLevel.info,
      ),
    );
  }

  /// Sets a user for the current scope.
  static void setUser({
    String? id,
    String? email,
    String? username,
    Map<String, String>? data,
  }) {
    Sentry.configureScope((scope) {
      scope.setUser(
        SentryUser(
          id: id,
          email: email,
          username: username,
          data: data,
        ),
      );
    });
  }

  /// Clears the current user.
  static void clearUser() {
    Sentry.configureScope((scope) {
      scope.setUser(null);
    });
  }

  /// Sets a tag on the current scope.
  static void setTag(String key, String value) {
    Sentry.configureScope((scope) {
      scope.setTag(key, value);
    });
  }

  /// Sets extra context on the current scope.
  static void setExtra(String key, dynamic value) {
    Sentry.configureScope((scope) {
      scope.setContexts(key, value);
    });
  }
}
