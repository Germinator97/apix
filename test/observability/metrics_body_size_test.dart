import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:apix/apix.dart';
import 'package:apix/src/http/body_size.dart';
import 'package:apix/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../regression/audit_harness.dart';

/// Body sizes in metrics are bytes, and are never obtained by rendering.
///
/// Both used to be `data.toString().length`: the length of Dart's rendering,
/// not a byte count — 23,960,010 for a 5,242,880-byte download, measured —
/// at the cost of building that string on the calling isolate (~160 ms for
/// the same download).
void main() {
  const fiveMegabytes = 5 * 1024 * 1024;

  group('utf8ByteLength counts what utf8.encode writes', () {
    for (final text in [
      '',
      'ascii',
      'é',
      'héllo',
      '€',
      '𝄞',
      'a𝄞b',
      '\uD800',
      '\uDC00',
      'x\uD800y',
      '\uD800\uD800\uDC00',
    ]) {
      test(jsonEncode(text), () {
        expect(utf8ByteLength(text), utf8.encode(text).length);
      });
    }
  });

  ({ApiClient client, List<RequestMetrics> metrics}) metered(
    ScriptedAdapter adapter,
  ) {
    final metrics = <RequestMetrics>[];
    final client = ApiClientFactory.create(
      baseUrl: 'https://api.test',
      httpClientAdapter: adapter,
      metricsConfig: MetricsConfig(
        trackRequestSize: true,
        trackResponseSize: true,
        onMetrics: metrics.add,
      ),
    );
    return (client: client, metrics: metrics);
  }

  group('responseSize is the body received, in bytes', () {
    test('a 5 MB download counts its bytes, not its rendering', () async {
      final (:client, :metrics) = metered(ScriptedAdapter((o, i) =>
          ResponseBody.fromBytes(Uint8List(fiveMegabytes), 200, headers: {
            Headers.contentTypeHeader: ['application/pdf'],
          })));

      await client.get<List<int>>('/files/report.pdf',
          options: Options(responseType: ResponseType.bytes));

      expect(metrics.single.responseSize, fiveMegabytes);
    });

    test('a JSON body sent without Content-Length is counted as it arrives',
        () async {
      final body = {'name': 'Zoé', 'items': List.generate(100, (i) => i)};
      final (:client, :metrics) =
          metered(ScriptedAdapter((o, i) => jsonResponse(body, 200)));

      await client.get<dynamic>('/items');

      expect(metrics.single.responseSize, utf8.encode(jsonEncode(body)).length);
    });

    test('a text body', () async {
      final (:client, :metrics) =
          metered(ScriptedAdapter((o, i) => textResponse('héllo', 200)));

      await client.get<dynamic>('/greeting');

      expect(metrics.single.responseSize, 6);
    });

    test('an error body is measured too', () async {
      final (:client, :metrics) = metered(ScriptedAdapter(
          (o, i) => jsonResponse({'message': 'nope', 'code': 'X'}, 400)));

      await expectLater(
          client.get<dynamic>('/items'), throwsA(isA<ClientException>()));

      expect(metrics.single.responseSize,
          utf8.encode(jsonEncode({'message': 'nope', 'code': 'X'})).length);
    });

    test(
        'without apix\'s transformer, Content-Length is read — unless the '
        'body was compressed', () async {
      for (final (headers, expected) in [
        (<String, List<String>>{}, 42),
        (
          {
            'content-encoding': ['gzip']
          },
          null
        ),
      ]) {
        final metrics = <RequestMetrics>[];
        final dio = Dio()
          ..httpClientAdapter =
              ScriptedAdapter((o, i) => ResponseBody.fromString(
                    jsonEncode({'id': 1}),
                    200,
                    headers: {
                      Headers.contentTypeHeader: ['application/json'],
                      Headers.contentLengthHeader: ['42'],
                      ...headers,
                    },
                  ))
          ..interceptors.add(MetricsInterceptor(
            config: MetricsConfig(
              trackResponseSize: true,
              onMetrics: metrics.add,
            ),
          ));

        await dio.get<dynamic>('https://api.test/items');

        expect(metrics.single.responseSize, expected, reason: '$headers');
      }
    });
  });

  group('requestSize is the body sent, in bytes', () {
    test('a 5 MB upload', () async {
      final (:client, :metrics) =
          metered(ScriptedAdapter((o, i) => jsonResponse({'ok': true}, 200)));

      await client.put<dynamic>('/files/report.pdf',
          data: Uint8List(fiveMegabytes));

      expect(metrics.single.requestSize, fiveMegabytes);
    });

    test('a JSON map is the size dio encoded, not its Dart rendering',
        () async {
      const body = {
        'name': 'Zoé',
        'tags': ['a', 'b']
      };
      final (:client, :metrics) =
          metered(ScriptedAdapter((o, i) => jsonResponse({'ok': true}, 200)));

      await client.post<dynamic>('/items', data: body);

      expect(metrics.single.requestSize, utf8.encode(jsonEncode(body)).length);
    });

    test('while in flight, only what is sized without encoding is known',
        () async {
      final release = Completer<void>();
      final adapter =
          ScriptedAdapter((o, i) => jsonResponse({'ok': true}, 200));
      final gated = _GatedAdapter(adapter, release.future);
      final metrics = <RequestMetrics>[];
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.test',
        httpClientAdapter: gated,
        metricsConfig: MetricsConfig(
          trackRequestSize: true,
          onMetrics: metrics.add,
        ),
      );
      final interceptor =
          client.dio.interceptors.whereType<MetricsInterceptor>().single;

      final bytes = client.put<dynamic>('/a', data: Uint8List(7));
      final map = client.post<dynamic>('/b', data: {'k': 'v'});
      await gated.bothArrived;

      final inFlight = interceptor.inFlightRequests.values
          .map((m) => (m.path, m.requestSize))
          .toSet();
      expect(inFlight, {('/a', 7), ('/b', null)});

      release.complete();
      await Future.wait([bytes, map]);

      final done = {for (final m in metrics) m.path: m.requestSize};
      expect(done, {'/a': 7, '/b': utf8.encode('{"k":"v"}').length});
    });
  });
}

/// Holds every request until the release future completes, so a test can
/// look at what is in flight.
class _GatedAdapter implements HttpClientAdapter {
  _GatedAdapter(this._inner, this._release);

  final HttpClientAdapter _inner;
  final Future<void> _release;
  final Completer<void> _both = Completer<void>();
  int _arrived = 0;

  Future<void> get bothArrived => _both.future;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (++_arrived == 2) _both.complete();
    await _release;
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}
