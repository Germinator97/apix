import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:apix/apix.dart';

class MockDio extends Mock implements Dio {}

class FakeOptions extends Fake implements Options {}

class FakeCancelToken extends Fake implements CancelToken {}

void main() {
  late MockDio mockDio;
  late ApiClient client;

  setUpAll(() {
    registerFallbackValue(FakeOptions());
    registerFallbackValue(FakeCancelToken());
  });

  setUp(() {
    mockDio = MockDio();
    when(() => mockDio.options).thenReturn(BaseOptions());
    when(() => mockDio.interceptors).thenReturn(Interceptors());

    const config = ApiClientConfig(baseUrl: 'https://api.example.com');
    client = ApiClient.withDio(mockDio, config);
  });

  Response<T> createResponse<T>(T data, {int statusCode = 200}) {
    return Response<T>(
      data: data,
      statusCode: statusCode,
      requestOptions: RequestOptions(path: '/test'),
    );
  }

  group('JSON Convenience Methods', () {
    group('postJson', () {
      test('sends POST with JSON content type', () async {
        final response = createResponse<Map<String, dynamic>>({'id': 1});
        when(() => mockDio.post<Map<String, dynamic>>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onSendProgress: any(named: 'onSendProgress'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        final result = await client.postJson('/users', {'name': 'John'});

        expect(result.data, equals({'id': 1}));

        final captured = verify(() => mockDio.post<Map<String, dynamic>>(
              '/users',
              data: {'name': 'John'},
              queryParameters: null,
              options: captureAny(named: 'options'),
              cancelToken: null,
              onSendProgress: null,
              onReceiveProgress: null,
            )).captured;

        final options = captured.first as Options;
        expect(options.contentType, equals('application/json'));
      });

      test('sends POST with custom headers', () async {
        final response = createResponse<Map<String, dynamic>>({'id': 1});
        when(() => mockDio.post<Map<String, dynamic>>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onSendProgress: any(named: 'onSendProgress'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        await client.postJson(
          '/users',
          {'name': 'John'},
          headers: {'X-Custom': 'value'},
        );

        final captured = verify(() => mockDio.post<Map<String, dynamic>>(
              '/users',
              data: {'name': 'John'},
              queryParameters: null,
              options: captureAny(named: 'options'),
              cancelToken: null,
              onSendProgress: null,
              onReceiveProgress: null,
            )).captured;

        final options = captured.first as Options;
        expect(options.headers?['X-Custom'], equals('value'));
      });
    });

    group('putJson', () {
      test('sends PUT with JSON content type', () async {
        final response = createResponse<Map<String, dynamic>>({'id': 1});
        when(() => mockDio.put<Map<String, dynamic>>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onSendProgress: any(named: 'onSendProgress'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        await client.putJson('/users/1', {'name': 'Jane'});

        final captured = verify(() => mockDio.put<Map<String, dynamic>>(
              '/users/1',
              data: {'name': 'Jane'},
              queryParameters: null,
              options: captureAny(named: 'options'),
              cancelToken: null,
              onSendProgress: null,
              onReceiveProgress: null,
            )).captured;

        final options = captured.first as Options;
        expect(options.contentType, equals('application/json'));
      });
    });

    group('patchJson', () {
      test('sends PATCH with JSON content type', () async {
        final response = createResponse<Map<String, dynamic>>({'id': 1});
        when(() => mockDio.patch<Map<String, dynamic>>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onSendProgress: any(named: 'onSendProgress'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        await client.patchJson('/users/1', {'name': 'Updated'});

        final captured = verify(() => mockDio.patch<Map<String, dynamic>>(
              '/users/1',
              data: {'name': 'Updated'},
              queryParameters: null,
              options: captureAny(named: 'options'),
              cancelToken: null,
              onSendProgress: null,
              onReceiveProgress: null,
            )).captured;

        final options = captured.first as Options;
        expect(options.contentType, equals('application/json'));
      });
    });
  });

  group('Typed Response Methods', () {
    group('getAndDecode', () {
      test('deserializes response with fromJson', () async {
        final response =
            createResponse<Map<String, dynamic>>({'id': 1, 'name': 'John'});
        when(() => mockDio.get<Map<String, dynamic>>(
              any(),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        final user = await client.getAndDecode<_TestUser>(
          '/users/1',
          _TestUser.fromJson,
        );

        expect(user.id, equals(1));
        expect(user.name, equals('John'));
      });
    });

    group('postAndDecode', () {
      test('posts JSON and deserializes response', () async {
        final response =
            createResponse<Map<String, dynamic>>({'id': 1, 'name': 'John'});
        when(() => mockDio.post<Map<String, dynamic>>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onSendProgress: any(named: 'onSendProgress'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        final user = await client.postAndDecode<_TestUser>(
          '/users',
          {'name': 'John'},
          _TestUser.fromJson,
        );

        expect(user.id, equals(1));
        expect(user.name, equals('John'));
      });
    });

    group('getListAndDecode', () {
      test('deserializes list response', () async {
        final response = createResponse<List<dynamic>>([
          {'id': 1, 'name': 'John'},
          {'id': 2, 'name': 'Jane'},
        ]);
        when(() => mockDio.get<List<dynamic>>(
              any(),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        final users = await client.getListAndDecode<_TestUser>(
          '/users',
          _TestUser.fromJson,
        );

        expect(users.length, equals(2));
        expect(users[0].name, equals('John'));
        expect(users[1].name, equals('Jane'));
      });
    });
  });
}

class _TestUser {
  final int id;
  final String name;

  _TestUser({required this.id, required this.name});

  static _TestUser fromJson(Map<String, dynamic> json) {
    return _TestUser(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}
