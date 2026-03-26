import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apix/apix.dart';

void main() {
  group('ApiClientConfig', () {
    test('creates with required baseUrl only', () {
      const config = ApiClientConfig(baseUrl: 'https://api.example.com');

      expect(config.baseUrl, equals('https://api.example.com'));
      expect(config.connectTimeout, equals(const Duration(seconds: 30)));
      expect(config.receiveTimeout, equals(const Duration(seconds: 30)));
      expect(config.sendTimeout, equals(const Duration(seconds: 30)));
      expect(config.headers, isNull);
      expect(config.interceptors, isNull);
      expect(config.dataKey, equals('data'));
    });

    test('creates with custom dataKey', () {
      const config = ApiClientConfig(
        baseUrl: 'https://api.example.com',
        dataKey: 'result',
      );

      expect(config.dataKey, equals('result'));
    });

    test('creates with custom timeouts', () {
      const config = ApiClientConfig(
        baseUrl: 'https://api.example.com',
        connectTimeout: Duration(seconds: 60),
        receiveTimeout: Duration(seconds: 45),
        sendTimeout: Duration(seconds: 15),
      );

      expect(config.connectTimeout, equals(const Duration(seconds: 60)));
      expect(config.receiveTimeout, equals(const Duration(seconds: 45)));
      expect(config.sendTimeout, equals(const Duration(seconds: 15)));
    });

    test('creates with headers', () {
      const config = ApiClientConfig(
        baseUrl: 'https://api.example.com',
        headers: {'Authorization': 'Bearer token', 'X-Custom': 'value'},
      );

      expect(config.headers, isNotNull);
      expect(config.headers!['Authorization'], equals('Bearer token'));
      expect(config.headers!['X-Custom'], equals('value'));
    });

    test('creates with interceptors', () {
      final interceptor = InterceptorsWrapper();
      final config = ApiClientConfig(
        baseUrl: 'https://api.example.com',
        interceptors: [interceptor],
      );

      expect(config.interceptors, isNotNull);
      expect(config.interceptors!.length, equals(1));
    });

    test('copyWith creates new config with updated values', () {
      const original = ApiClientConfig(
        baseUrl: 'https://api.example.com',
        connectTimeout: Duration(seconds: 30),
      );

      final copied = original.copyWith(
        baseUrl: 'https://new-api.example.com',
        connectTimeout: const Duration(seconds: 60),
      );

      expect(copied.baseUrl, equals('https://new-api.example.com'));
      expect(copied.connectTimeout, equals(const Duration(seconds: 60)));
      expect(original.baseUrl, equals('https://api.example.com'));
      expect(original.connectTimeout, equals(const Duration(seconds: 30)));
    });

    test('copyWith updates dataKey', () {
      const original = ApiClientConfig(baseUrl: 'https://api.example.com');

      final copied = original.copyWith(dataKey: 'result');

      expect(copied.dataKey, equals('result'));
      expect(original.dataKey, equals('data'));
    });
  });

  group('ApiClientFactory', () {
    test('creates with minimal config', () {
      final client =
          ApiClientFactory.create(baseUrl: 'https://api.example.com');

      expect(client.baseUrl, equals('https://api.example.com'));
      expect(client.config.connectTimeout, equals(const Duration(seconds: 30)));
      expect(client.dio, isA<Dio>());

      client.close();
    });

    test('creates with custom timeouts', () {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 45),
      );

      expect(client.config.connectTimeout, equals(const Duration(seconds: 60)));
      expect(client.config.receiveTimeout, equals(const Duration(seconds: 45)));

      client.close();
    });

    test('creates with custom headers', () {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        headers: {'Authorization': 'Bearer token'},
      );

      expect(
          client.dio.options.headers['Authorization'], equals('Bearer token'));

      client.close();
    });

    test('creates with interceptors', () {
      final interceptor = InterceptorsWrapper();
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        interceptors: [interceptor],
      );

      expect(client.dio.interceptors, contains(interceptor));

      client.close();
    });

    test('creates from config', () {
      const config = ApiClientConfig(
        baseUrl: 'https://api.example.com',
        connectTimeout: Duration(seconds: 60),
      );

      final client = ApiClientFactory.fromConfig(config);

      expect(client.baseUrl, equals('https://api.example.com'));
      expect(client.config, equals(config));

      client.close();
    });

    test('creates with custom Dio instance', () {
      final dio = Dio();
      const config = ApiClientConfig(baseUrl: 'https://api.example.com');

      final client = ApiClient(dio, config);

      expect(client.dio, same(dio));
      expect(client.config, equals(config));

      client.close();
    });

    test('configures Dio options correctly', () {
      final client = ApiClientFactory.create(
        baseUrl: 'https://api.example.com',
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 15),
      );

      expect(client.dio.options.baseUrl, equals('https://api.example.com'));
      expect(
        client.dio.options.connectTimeout,
        equals(const Duration(seconds: 60)),
      );
      expect(
        client.dio.options.receiveTimeout,
        equals(const Duration(seconds: 45)),
      );
      expect(
        client.dio.options.sendTimeout,
        equals(const Duration(seconds: 15)),
      );

      client.close();
    });

    test('default timeout is 30 seconds', () {
      final client =
          ApiClientFactory.create(baseUrl: 'https://api.example.com');

      expect(
        client.dio.options.connectTimeout,
        equals(const Duration(seconds: 30)),
      );
      expect(
        client.dio.options.receiveTimeout,
        equals(const Duration(seconds: 30)),
      );
      expect(
        client.dio.options.sendTimeout,
        equals(const Duration(seconds: 30)),
      );

      client.close();
    });
  });
}
