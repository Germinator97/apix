import 'dart:convert';

import 'package:apix/apix.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records its own lifecycle so a test can assert not just that a span was
/// opened, but that it was closed — exactly once.
class _FakeSpan implements ApiSpan {
  _FakeSpan(this.description);

  final String description;
  final Map<String, Object?> data = {};
  int finishCount = 0;
  int? finishedWith;

  bool get isOpen => finishCount == 0;

  @override
  void setData(String key, Object? value) => data[key] = value;

  @override
  void finish({int? statusCode}) {
    finishCount++;
    finishedWith = statusCode;
  }
}

class _SpanRecorder {
  final List<_FakeSpan> spans = [];

  ApiSpan? start(String operation, String description) {
    final span = _FakeSpan(description);
    spans.add(span);
    return span;
  }

  Iterable<_FakeSpan> get open => spans.where((s) => s.isOpen);
}

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.statusCode);

  final int statusCode;
  int hits = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    hits++;
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'value': 'ok'})),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _SpanRecorder recorder;
  TracingConfig configFor() => TracingConfig(startSpan: recorder.start);

  setUp(() => recorder = _SpanRecorder());

  group('TracingInterceptor', () {
    test('opens one span per request, with method and path attached', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        tracingConfig: configFor(),
        httpClientAdapter: _StatusAdapter(200),
      );

      await client.get<dynamic>('/accounts/statements');

      expect(recorder.spans, hasLength(1));
      final span = recorder.spans.single;
      expect(span.description, equals('GET /accounts/statements'));
      expect(span.data['http.request.method'], equals('GET'));
      expect(span.data['url.path'], equals('/accounts/statements'));
    });

    // A span that is opened and never closed is worse than no span: it skews
    // every trace it sits in, and nothing raises.
    test('closes the span on success', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        tracingConfig: configFor(),
        httpClientAdapter: _StatusAdapter(200),
      );

      await client.get<dynamic>('/ok');

      expect(recorder.open, isEmpty);
      expect(recorder.spans.single.finishedWith, equals(200));
    });

    test('closes the span on error', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        tracingConfig: configFor(),
        httpClientAdapter: _StatusAdapter(500),
      );

      try {
        await client.get<dynamic>('/boom');
      } on ApiException {
        // The span's fate is the subject here, not the failure.
      }

      expect(recorder.open, isEmpty);
      expect(recorder.spans.single.finishedWith, equals(500));
    });

    // Found by this test, not by reading: an unconditional start opened one
    // span per attempt while only the last reached onError, leaking the rest.
    test('a retried request produces one span, closed once', () async {
      final adapter = _StatusAdapter(503);
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        retryConfig: const RetryConfig(maxAttempts: 2, baseDelayMs: 1),
        tracingConfig: configFor(),
        httpClientAdapter: adapter,
      );

      try {
        await client.get<dynamic>('/flaky');
      } on ApiException {
        // ignored
      }

      expect(adapter.hits, equals(3), reason: 'initial call plus two retries');
      expect(
        recorder.spans,
        hasLength(1),
        reason: 'the span must cover the whole logical request — which is what '
            'the caller waited for, backoff included',
      );
      expect(recorder.open, isEmpty);
      expect(
        recorder.spans.single.finishCount,
        equals(1),
        reason: 'finishing one span twice is how a trace gets impossible '
            'durations',
      );
    });

    // The ordering trap this interceptor is placed to avoid: the cache answers
    // with handler.resolve(), which ends the chain without running the
    // following onResponse handlers.
    test('a cache hit leaves no span open', () async {
      final adapter = _StatusAdapter(200);
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        cacheConfig: CacheConfig(
          strategy: CacheStrategy.cacheFirst,
          defaultTtl: const Duration(minutes: 5),
        ),
        tracingConfig: configFor(),
        httpClientAdapter: adapter,
      );

      await client.get<dynamic>('/profile'); // populates the cache
      await client.get<dynamic>('/profile'); // served from cache

      expect(adapter.hits, equals(1), reason: 'the second call must be a hit');
      expect(
        recorder.open,
        isEmpty,
        reason: 'a span opened before the cache would dangle forever on '
            'exactly the requests that were fastest',
      );
      expect(
        recorder.spans,
        hasLength(1),
        reason: 'a cached response spent no time on the network — tracing it '
            'would report a duration that never happened',
      );
    });

    test('traces nothing when disabled', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        tracingConfig: TracingConfig(
          enabled: false,
          startSpan: recorder.start,
        ),
        httpClientAdapter: _StatusAdapter(200),
      );

      await client.get<dynamic>('/ok');

      expect(recorder.spans, isEmpty);
    });

    test('a starter returning null is not an error', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        tracingConfig: const TracingConfig(startSpan: _noSpan),
        httpClientAdapter: _StatusAdapter(200),
      );

      final response = await client.get<dynamic>('/ok');

      expect(
        response.statusCode,
        equals(200),
        reason: 'no ambient transaction is the common case — it must not '
            'disturb the request',
      );
    });

    test('is absent unless asked for', () async {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: _StatusAdapter(200),
      );

      await client.get<dynamic>('/ok');

      expect(recorder.spans, isEmpty);
    });
  });
}

ApiSpan? _noSpan(String operation, String description) => null;
