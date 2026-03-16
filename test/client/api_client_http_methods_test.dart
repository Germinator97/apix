import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:apix/apix.dart';

class MockDio extends Mock implements Dio {}

class FakeOptions extends Fake implements Options {}

class FakeCancelToken extends Fake implements CancelToken {}

class FakeRequestOptions extends Fake implements RequestOptions {}

void main() {
  late MockDio mockDio;
  late ApiClient client;

  setUpAll(() {
    registerFallbackValue(FakeOptions());
    registerFallbackValue(FakeCancelToken());
    registerFallbackValue(FakeRequestOptions());
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

  group('ApiClient HTTP Methods', () {
    group('get', () {
      test('sends GET request to path', () async {
        final response = createResponse({'id': 1});
        when(() => mockDio.get<dynamic>(
              any(),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        final result = await client.get<dynamic>('/users');

        expect(result.data, equals({'id': 1}));
        verify(() => mockDio.get<dynamic>(
              '/users',
              queryParameters: null,
              options: null,
              cancelToken: null,
              onReceiveProgress: null,
            )).called(1);
      });

      test('sends GET request with query parameters', () async {
        final response = createResponse<List<dynamic>>(<dynamic>[]);
        when(() => mockDio.get<dynamic>(
              any(),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        await client
            .get<dynamic>('/users', queryParameters: {'page': 1, 'limit': 10});

        verify(() => mockDio.get<dynamic>(
              '/users',
              queryParameters: {'page': 1, 'limit': 10},
              options: null,
              cancelToken: null,
              onReceiveProgress: null,
            )).called(1);
      });

      test('sends GET request with options', () async {
        final response =
            createResponse<Map<String, dynamic>>(<String, dynamic>{});
        final options = Options(headers: {'X-Custom': 'value'});
        when(() => mockDio.get<dynamic>(
              any(),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        await client.get<dynamic>('/users', options: options);

        verify(() => mockDio.get<dynamic>(
              '/users',
              queryParameters: null,
              options: options,
              cancelToken: null,
              onReceiveProgress: null,
            )).called(1);
      });
    });

    group('post', () {
      test('sends POST request with data', () async {
        final response = createResponse({'id': 1}, statusCode: 201);
        when(() => mockDio.post<dynamic>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onSendProgress: any(named: 'onSendProgress'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        final result =
            await client.post<dynamic>('/users', data: {'name': 'John'});

        expect(result.statusCode, equals(201));
        verify(() => mockDio.post<dynamic>(
              '/users',
              data: {'name': 'John'},
              queryParameters: null,
              options: null,
              cancelToken: null,
              onSendProgress: null,
              onReceiveProgress: null,
            )).called(1);
      });

      test('sends POST request with query parameters', () async {
        final response =
            createResponse<Map<String, dynamic>>(<String, dynamic>{});
        when(() => mockDio.post<dynamic>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onSendProgress: any(named: 'onSendProgress'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        await client.post<dynamic>('/users', queryParameters: {'async': true});

        verify(() => mockDio.post<dynamic>(
              '/users',
              data: null,
              queryParameters: {'async': true},
              options: null,
              cancelToken: null,
              onSendProgress: null,
              onReceiveProgress: null,
            )).called(1);
      });
    });

    group('put', () {
      test('sends PUT request with data', () async {
        final response = createResponse({'id': 1, 'name': 'Jane'});
        when(() => mockDio.put<dynamic>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onSendProgress: any(named: 'onSendProgress'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        final result =
            await client.put<dynamic>('/users/1', data: {'name': 'Jane'});

        expect(result.data, equals({'id': 1, 'name': 'Jane'}));
        verify(() => mockDio.put<dynamic>(
              '/users/1',
              data: {'name': 'Jane'},
              queryParameters: null,
              options: null,
              cancelToken: null,
              onSendProgress: null,
              onReceiveProgress: null,
            )).called(1);
      });
    });

    group('delete', () {
      test('sends DELETE request', () async {
        final response = createResponse(null, statusCode: 204);
        when(() => mockDio.delete<dynamic>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
            )).thenAnswer((_) async => response);

        final result = await client.delete<dynamic>('/users/1');

        expect(result.statusCode, equals(204));
        verify(() => mockDio.delete<dynamic>(
              '/users/1',
              data: null,
              queryParameters: null,
              options: null,
              cancelToken: null,
            )).called(1);
      });

      test('sends DELETE request with data', () async {
        final response = createResponse(null);
        when(() => mockDio.delete<dynamic>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
            )).thenAnswer((_) async => response);

        await client.delete<dynamic>('/users', data: {
          'ids': [1, 2, 3]
        });

        verify(() => mockDio.delete<dynamic>(
              '/users',
              data: {
                'ids': [1, 2, 3]
              },
              queryParameters: null,
              options: null,
              cancelToken: null,
            )).called(1);
      });
    });

    group('patch', () {
      test('sends PATCH request with data', () async {
        final response = createResponse({'id': 1, 'name': 'Updated'});
        when(() => mockDio.patch<dynamic>(
              any(),
              data: any(named: 'data'),
              queryParameters: any(named: 'queryParameters'),
              options: any(named: 'options'),
              cancelToken: any(named: 'cancelToken'),
              onSendProgress: any(named: 'onSendProgress'),
              onReceiveProgress: any(named: 'onReceiveProgress'),
            )).thenAnswer((_) async => response);

        final result =
            await client.patch<dynamic>('/users/1', data: {'name': 'Updated'});

        expect(result.data, equals({'id': 1, 'name': 'Updated'}));
        verify(() => mockDio.patch<dynamic>(
              '/users/1',
              data: {'name': 'Updated'},
              queryParameters: null,
              options: null,
              cancelToken: null,
              onSendProgress: null,
              onReceiveProgress: null,
            )).called(1);
      });
    });
  });
}
