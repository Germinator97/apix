/// Apix Example
///
/// This example demonstrates the basic usage of the apix package.
library;

import 'package:apix/apix.dart';

/// Simple example showing API client creation and usage.
void main() async {
  // Create an API client with factory
  final client = ApiClientFactory.create(
    baseUrl: 'https://api.example.com',
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  );

  // Add retry interceptor
  client.dio.interceptors.add(
    RetryInterceptor(
      config: const RetryConfig(
        maxAttempts: 3,
        retryStatusCodes: [500, 502, 503, 504],
      ),
      dio: client.dio,
    ),
  );

  // Add cache interceptor
  final cacheInterceptor = CacheInterceptor(
    config: CacheConfig(
      strategy: CacheStrategy.networkFirst,
      defaultTtl: const Duration(minutes: 5),
    ),
  );
  cacheInterceptor.setDio(client.dio);
  client.dio.interceptors.add(cacheInterceptor);

  // Add logger interceptor
  client.dio.interceptors.add(
    LoggerInterceptor(
      config: const LoggerConfig(
        level: LogLevel.info,
        redactedHeaders: ['Authorization'],
      ),
    ),
  );

  // Make a GET request with typed response
  try {
    final user = await client.getAndDecode(
      '/users/1',
      (json) => User.fromJson(json),
    );
    print('User: ${user.name}');
  } on HttpException catch (e) {
    print('HTTP Error: ${e.statusCode}');
  } on NetworkException catch (e) {
    print('Network Error: ${e.message}');
  }

  // Use Result type for functional error handling
  final result = await client.get('/users').getResult();
  result.when(
    success: (response) => print('Got ${response.data}'),
    failure: (error) => print('Error: ${error.message}'),
  );

  // Clean up
  client.close();
}

/// Example user model.
class User {
  final int id;
  final String name;
  final String email;

  User({required this.id, required this.name, required this.email});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }
}
