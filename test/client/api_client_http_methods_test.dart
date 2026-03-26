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
    client = ApiClient(mockDio, config);
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

  // ========== Typed Response Methods ==========

  group('ApiClient Parse/Decode Methods', () {
    void stubGet(dynamic data) {
      when(() => mockDio.get<dynamic>(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).thenAnswer((_) async => createResponse(data));
    }

    void stubGetTyped<T>(T data) {
      when(() => mockDio.get<T>(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).thenAnswer((_) async => createResponse<T>(data));
    }

    void stubPost(dynamic data) {
      when(() => mockDio.post<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onSendProgress: any(named: 'onSendProgress'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).thenAnswer((_) async => createResponse(data));
    }

    void stubPostTyped<T>(T data) {
      when(() => mockDio.post<T>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onSendProgress: any(named: 'onSendProgress'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).thenAnswer((_) async => createResponse<T>(data));
    }

    group('getAndParse', () {
      test('parses response.data with parser', () async {
        stubGet(42);

        final result =
            await client.getAndParse('/count', (data) => data as int);

        expect(result, equals(42));
      });
    });

    group('getAndDecode', () {
      test('deserializes response.data as Map', () async {
        stubGetTyped<Map<String, dynamic>>({'id': 1, 'name': 'John'});

        final result = await client.getAndDecode(
          '/users/1',
          (json) => json['name'] as String,
        );

        expect(result, equals('John'));
      });
    });

    group('postAndParse', () {
      test('parses response.data with parser', () async {
        stubPost('created');

        final result = await client.postAndParse(
          '/action',
          {'key': 'value'},
          (data) => data as String,
        );

        expect(result, equals('created'));
      });
    });

    group('postAndDecode', () {
      test('deserializes response.data as Map', () async {
        stubPostTyped<Map<String, dynamic>>({'id': 1, 'name': 'John'});

        final result = await client.postAndDecode(
          '/users',
          {'name': 'John'},
          (json) => json['name'] as String,
        );

        expect(result, equals('John'));
      });
    });
  });

  // ========== Data Extraction Methods ==========

  group('ApiClient Data Methods (envelope unwrapping)', () {
    void stubGet(dynamic data) {
      when(() => mockDio.get<dynamic>(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).thenAnswer((_) async => createResponse(data));
    }

    void stubPost(dynamic data) {
      when(() => mockDio.post<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onSendProgress: any(named: 'onSendProgress'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).thenAnswer((_) async => createResponse(data));
    }

    // ---------- GET Data ----------

    group('getAndParseData', () {
      test('extracts and parses data from envelope', () async {
        stubGet({'data': '2024-01-01'});

        final result = await client.getAndParseData(
          '/time',
          (data) => DateTime.parse(data as String),
        );

        expect(result, equals(DateTime(2024, 1, 1)));
      });
    });

    group('getAndParseDataOrNull', () {
      test('returns parsed data when present', () async {
        stubGet({'data': 42});

        final result = await client.getAndParseDataOrNull(
          '/count',
          (data) => data as int,
        );

        expect(result, equals(42));
      });

      test('returns null when data key is null', () async {
        stubGet({'data': null});

        final result = await client.getAndParseDataOrNull(
          '/count',
          (data) => data as int,
        );

        expect(result, isNull);
      });
    });

    group('getAndDecodeData', () {
      test('extracts and deserializes JSON object from envelope', () async {
        stubGet({
          'data': {'id': 1, 'name': 'John'},
        });

        final result = await client.getAndDecodeData(
          '/users/1',
          (json) => json['name'] as String,
        );

        expect(result, equals('John'));
      });
    });

    group('getAndDecodeDataOrNull', () {
      test('returns deserialized object when present', () async {
        stubGet({
          'data': {'id': 1, 'name': 'John'},
        });

        final result = await client.getAndDecodeDataOrNull(
          '/users/1',
          (json) => json['name'] as String,
        );

        expect(result, equals('John'));
      });

      test('returns null when data key is null', () async {
        stubGet({'data': null});

        final result = await client.getAndDecodeDataOrNull(
          '/users/1',
          (json) => json['name'] as String,
        );

        expect(result, isNull);
      });
    });

    group('getListAndDecodeData', () {
      test('extracts and deserializes list from envelope', () async {
        stubGet({
          'data': [
            {'id': 1},
            {'id': 2},
          ],
        });

        final result = await client.getListAndDecodeData(
          '/users',
          (json) => json['id'] as int,
        );

        expect(result, equals([1, 2]));
      });
    });

    group('getListAndDecodeDataOrNull', () {
      test('returns list when present', () async {
        stubGet({
          'data': [
            {'id': 1},
          ],
        });

        final result = await client.getListAndDecodeDataOrNull(
          '/users',
          (json) => json['id'] as int,
        );

        expect(result, equals([1]));
      });

      test('returns null when data key is null', () async {
        stubGet({'data': null});

        final result = await client.getListAndDecodeDataOrNull(
          '/users',
          (json) => json['id'] as int,
        );

        expect(result, isNull);
      });
    });

    group('getListAndDecodeDataOrEmpty', () {
      test('returns list when present', () async {
        stubGet({
          'data': [
            {'id': 1},
          ],
        });

        final result = await client.getListAndDecodeDataOrEmpty(
          '/users',
          (json) => json['id'] as int,
        );

        expect(result, equals([1]));
      });

      test('returns empty list when data key is null', () async {
        stubGet({'data': null});

        final result = await client.getListAndDecodeDataOrEmpty(
          '/users',
          (json) => json['id'] as int,
        );

        expect(result, isEmpty);
      });
    });

    group('getListAndParseData', () {
      test('extracts and parses list from envelope', () async {
        stubGet({
          'data': ['admin', 'editor'],
        });

        final result = await client.getListAndParseData(
          '/roles',
          (item) => item as String,
        );

        expect(result, equals(['admin', 'editor']));
      });
    });

    group('getListAndParseDataOrNull', () {
      test('returns null when data key is null', () async {
        stubGet({'data': null});

        final result = await client.getListAndParseDataOrNull(
          '/roles',
          (item) => item as String,
        );

        expect(result, isNull);
      });
    });

    group('getListAndParseDataOrEmpty', () {
      test('returns empty list when data key is null', () async {
        stubGet({'data': null});

        final result = await client.getListAndParseDataOrEmpty(
          '/roles',
          (item) => item as String,
        );

        expect(result, isEmpty);
      });
    });

    // ---------- POST Data ----------

    group('postAndParseData', () {
      test('extracts and parses data from envelope', () async {
        stubPost({'data': 'token-123'});

        final result = await client.postAndParseData(
          '/auth',
          {'email': 'test@test.com'},
          (data) => data as String,
        );

        expect(result, equals('token-123'));
      });
    });

    group('postAndParseDataOrNull', () {
      test('returns null when data key is null', () async {
        stubPost({'data': null});

        final result = await client.postAndParseDataOrNull(
          '/auth',
          {'email': 'test@test.com'},
          (data) => data as String,
        );

        expect(result, isNull);
      });
    });

    group('postAndDecodeData', () {
      test('extracts and deserializes JSON object from envelope', () async {
        stubPost({
          'data': {'id': 1, 'name': 'John'},
        });

        final result = await client.postAndDecodeData(
          '/users',
          {'name': 'John'},
          (json) => json['id'] as int,
        );

        expect(result, equals(1));
      });
    });

    group('postAndDecodeDataOrNull', () {
      test('returns null when data key is null', () async {
        stubPost({'data': null});

        final result = await client.postAndDecodeDataOrNull(
          '/users',
          {'name': 'John'},
          (json) => json['id'] as int,
        );

        expect(result, isNull);
      });
    });

    group('postListAndDecodeData', () {
      test('extracts and deserializes list from envelope', () async {
        stubPost({
          'data': [
            {'id': 1},
            {'id': 2},
          ],
        });

        final result = await client.postListAndDecodeData(
          '/search',
          {'query': 'test'},
          (json) => json['id'] as int,
        );

        expect(result, equals([1, 2]));
      });
    });

    group('postListAndDecodeDataOrNull', () {
      test('returns null when data key is null', () async {
        stubPost({'data': null});

        final result = await client.postListAndDecodeDataOrNull(
          '/search',
          {'query': 'test'},
          (json) => json['id'] as int,
        );

        expect(result, isNull);
      });
    });

    group('postListAndDecodeDataOrEmpty', () {
      test('returns empty list when data key is null', () async {
        stubPost({'data': null});

        final result = await client.postListAndDecodeDataOrEmpty(
          '/search',
          {'query': 'test'},
          (json) => json['id'] as int,
        );

        expect(result, isEmpty);
      });
    });

    group('postListAndParseData', () {
      test('extracts and parses list from envelope', () async {
        stubPost({
          'data': [1, 2, 3],
        });

        final result = await client.postListAndParseData(
          '/ids',
          {'filter': 'active'},
          (item) => item as int,
        );

        expect(result, equals([1, 2, 3]));
      });
    });

    group('postListAndParseDataOrNull', () {
      test('returns null when data key is null', () async {
        stubPost({'data': null});

        final result = await client.postListAndParseDataOrNull(
          '/ids',
          {'filter': 'active'},
          (item) => item as int,
        );

        expect(result, isNull);
      });
    });

    group('postListAndParseDataOrEmpty', () {
      test('returns empty list when data key is null', () async {
        stubPost({'data': null});

        final result = await client.postListAndParseDataOrEmpty(
          '/ids',
          {'filter': 'active'},
          (item) => item as int,
        );

        expect(result, isEmpty);
      });
    });

    // ---------- Custom dataKey ----------

    group('custom dataKey', () {
      test('uses config dataKey for extraction', () async {
        final customClient = ApiClient(
          mockDio,
          const ApiClientConfig(
            baseUrl: 'https://api.example.com',
            dataKey: 'result',
          ),
        );

        stubGet({
          'result': {'id': 1, 'name': 'John'},
        });

        final result = await customClient.getAndDecodeData(
          '/users/1',
          (json) => json['name'] as String,
        );

        expect(result, equals('John'));
      });
    });
  });
}
