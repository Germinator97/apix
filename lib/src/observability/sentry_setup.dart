import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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

  const SentrySetupOptions({
    required this.dsn,
    required this.environment,
    this.enabled = true,
    this.sampleRate = 1.0,
    this.tracesSampleRate = 0.5,
    this.profilesSampleRate = 0.1,
    this.replayOnErrorSampleRate = 1.0,
    this.replaySessionSampleRate = 0.1,
    this.sendDefaultPii = true,
    this.captureFailedRequests = true,
    this.anrEnabled = false,
    this.filterNetworkNoise = true,
    this.minTransactionDurationMs = 100,
    this.customBeforeSend,
    this.customBeforeSendTransaction,
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

    _isInitialized = true;

    await SentryFlutter.init(
      (sentryOptions) {
        sentryOptions.dsn = options.dsn;
        sentryOptions.environment = options.environment;

        sentryOptions.sendDefaultPii = options.sendDefaultPii;
        sentryOptions.sampleRate = options.sampleRate;

        // Disable tracing in debug mode
        sentryOptions.tracesSampleRate =
            kDebugMode ? 0.0 : options.tracesSampleRate;
        // Note: profilesSampleRate is experimental and may be removed
        // sentryOptions.profilesSampleRate =
        //     kDebugMode ? 0.0 : options.profilesSampleRate;

        // Note: Replay options available in newer versions
        // sentryOptions.replay.onErrorSampleRate = options.replayOnErrorSampleRate;
        // sentryOptions.replay.sessionSampleRate = options.replaySessionSampleRate;

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
            (transaction) => _beforeSendTransaction(
                  transaction,
                  options,
                );
      },
      appRunner: appRunner,
    );
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
    SentrySetupOptions options,
  ) {
    // Filter short transactions
    final duration = transaction.timestamp?.difference(
      transaction.startTimestamp,
    );
    if (duration != null &&
        duration.inMilliseconds < options.minTransactionDurationMs) {
      return null;
    }

    // Call custom beforeSendTransaction if provided
    if (options.customBeforeSendTransaction != null) {
      return options.customBeforeSendTransaction!(transaction, Hint());
    }

    return transaction;
  }

  /// Checks if an event is a network noise error that should be filtered.
  static bool isNetworkNoiseError(SentryEvent event) {
    final exceptions = event.exceptions ?? [];

    for (final exception in exceptions) {
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
    const networkExceptionTypes = [
      'SocketException',
      'HandshakeException',
      'ClientException',
      'TimeoutException',
      'HttpException',
      'TlsException',
    ];

    return networkExceptionTypes.any((t) => type.contains(t));
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
