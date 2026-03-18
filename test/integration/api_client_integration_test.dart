import 'package:apix/apix.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockHttpClientAdapter extends Mock implements HttpClientAdapter {}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Stream<List<int>>.empty());
  });

  group('ApiClient Integration Tests', () {
    group('ApiClientFactory', () {
      test('creates client with base URL', () {
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
        );

        expect(client, isNotNull);
        expect(client.dio.options.baseUrl, 'https://api.example.com');
        client.close();
      });

      test('creates client with custom timeouts', () {
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 20),
        );

        expect(client.dio.options.connectTimeout, const Duration(seconds: 10));
        expect(client.dio.options.receiveTimeout, const Duration(seconds: 15));
        expect(client.dio.options.sendTimeout, const Duration(seconds: 20));
        client.close();
      });

      test('creates client with custom headers', () {
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          headers: {'X-App-Version': '1.0.0', 'X-Platform': 'test'},
        );

        expect(client.dio.options.headers['X-App-Version'], '1.0.0');
        expect(client.dio.options.headers['X-Platform'], 'test');
        client.close();
      });

      test('creates client with custom interceptors', () {
        final customInterceptor = InterceptorsWrapper();
        final client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          interceptors: [customInterceptor],
        );

        expect(client.dio.interceptors, contains(customInterceptor));
        client.close();
      });

      test('creates client from config', () {
        final config = ApiClientConfig(
          baseUrl: 'https://api.example.com',
          connectTimeout: const Duration(seconds: 60),
          headers: {'Authorization': 'Bearer test'},
        );

        final client = ApiClientFactory.fromConfig(config);

        expect(client.dio.options.baseUrl, 'https://api.example.com');
        expect(client.dio.options.connectTimeout, const Duration(seconds: 60));
        expect(client.dio.options.headers['Authorization'], 'Bearer test');
        client.close();
      });
    });

    group('ApiClientConfig', () {
      test('requires baseUrl', () {
        const config = ApiClientConfig(baseUrl: 'https://api.example.com');
        expect(config.baseUrl, 'https://api.example.com');
      });

      test('has sensible defaults', () {
        const config = ApiClientConfig(baseUrl: 'https://api.example.com');

        expect(config.connectTimeout, const Duration(seconds: 30));
        expect(config.receiveTimeout, const Duration(seconds: 30));
        expect(config.sendTimeout, const Duration(seconds: 30));
        expect(config.defaultContentType, 'application/json');
      });

      test('copyWith creates modified copy', () {
        const original = ApiClientConfig(
          baseUrl: 'https://api.example.com',
          connectTimeout: Duration(seconds: 10),
        );
        final modified = original.copyWith(
          receiveTimeout: const Duration(seconds: 20),
        );

        expect(modified.baseUrl, 'https://api.example.com');
        expect(modified.connectTimeout, const Duration(seconds: 10));
        expect(modified.receiveTimeout, const Duration(seconds: 20));
      });
    });

    group('Full Request Flow with Mock', () {
      late ApiClient client;
      late MockHttpClientAdapter mockAdapter;

      setUp(() {
        mockAdapter = MockHttpClientAdapter();
        client = ApiClientFactory.create(
          baseUrl: 'https://api.example.com',
          httpClientAdapter: mockAdapter,
        );
      });

      tearDown(() {
        client.close();
      });

      test('successful GET request', () async {
        when(() => mockAdapter.fetch(any(), any(), any())).thenAnswer(
          (_) async => ResponseBody.fromString(
            '{"id": 1, "name": "Test"}',
            200,
            headers: {'content-type': ['application/json']},
          ),
        );

        final response = await client.get('/users/1');

        expect(response.statusCode, 200);
        expect(response.data['id'], 1);
        expect(response.data['name'], 'Test');
      });

      test('successful POST request', () async {
        when(() => mockAdapter.fetch(any(), any(), any())).thenAnswer(
          (_) async => ResponseBody.fromString(
            '{"id": 1, "created": true}',
            201,
            headers: {'content-type': ['application/json']},
          ),
        );

        final response = await client.post(
          '/users',
          data: {'name': 'New User'},
        );

        expect(response.statusCode, 201);
        expect(response.data['created'], true);
      });

      test('handles 404 response as DioException', () async {
        when(() => mockAdapter.fetch(any(), any(), any())).thenAnswer(
          (_) async => ResponseBody.fromString(
            '{"error": "Not found"}',
            404,
            headers: {'content-type': ['application/json']},
          ),
        );

        expect(
          () => client.get('/nonexistent'),
          throwsA(isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            404,
          )),
        );
      });

      test('handles 500 response as DioException', () async {
        when(() => mockAdapter.fetch(any(), any(), any())).thenAnswer(
          (_) async => ResponseBody.fromString(
            '{"error": "Server error"}',
            500,
            headers: {'content-type': ['application/json']},
          ),
        );

        expect(
          () => client.get('/broken'),
          throwsA(isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            500,
          )),
        );
      });

      test('handles network error as DioException', () async {
        when(() => mockAdapter.fetch(any(), any(), any())).thenThrow(
          DioException(
            type: DioExceptionType.connectionError,
            requestOptions: RequestOptions(path: '/test'),
            message: 'Connection failed',
          ),
        );

        expect(
          () => client.get('/test'),
          throwsA(isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.connectionError,
          )),
        );
      });

      test('handles timeout error as DioException', () async {
        when(() => mockAdapter.fetch(any(), any(), any())).thenThrow(
          DioException(
            type: DioExceptionType.connectionTimeout,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );

        expect(
          () => client.get('/test'),
          throwsA(isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.connectionTimeout,
          )),
        );
      });
    });

    group('Exception Hierarchy', () {
      test('NetworkException has message', () {
        const error = NetworkException(message: 'Connection failed');
        expect(error.message, 'Connection failed');
        expect(error, isA<ApiException>());
        expect(error.toString(), contains('Connection failed'));
      });

      test('TimeoutException has duration', () {
        const error = TimeoutException(
          message: 'Request timeout',
          duration: Duration(seconds: 30),
        );
        expect(error.duration, const Duration(seconds: 30));
        expect(error, isA<NetworkException>());
      });

      test('ConnectionException extends NetworkException', () {
        const error = ConnectionException(message: 'No internet');
        expect(error, isA<NetworkException>());
        expect(error.toString(), contains('No internet'));
      });

      test('HttpException has status code', () {
        const error = HttpException(
          message: 'Not found',
          statusCode: 404,
        );
        expect(error.statusCode, 404);
        expect(error, isA<ApiException>());
      });

      test('NotFoundException defaults to 404', () {
        const error = NotFoundException();
        expect(error.statusCode, 404);
        expect(error, isA<ClientException>());
      });

      test('UnauthorizedException defaults to 401', () {
        const error = UnauthorizedException();
        expect(error.statusCode, 401);
        expect(error, isA<ClientException>());
      });

      test('ForbiddenException defaults to 403', () {
        const error = ForbiddenException();
        expect(error.statusCode, 403);
        expect(error, isA<ClientException>());
      });

      test('ServerException requires statusCode', () {
        const error = ServerException(message: 'Internal error', statusCode: 500);
        expect(error.statusCode, 500);
        expect(error, isA<HttpException>());
      });
    });
  });
}
