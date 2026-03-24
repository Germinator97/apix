import '../errors/api_exception.dart';

/// A type that represents either a success value or a failure.
///
/// Use [Result] for functional error handling as an alternative to exceptions.
///
/// Example:
/// ```dart
/// final result = await client.get('/users').getResult();
///
/// result.fold(
///   onSuccess: (users) => print('Got ${users.length} users'),
///   onFailure: (error) => print('Error: ${error.message}'),
/// );
/// ```
sealed class Result<T, E extends ApiException> {
  const Result._();

  /// Creates a successful result with [value].
  const factory Result.success(T value) = Success<T, E>;

  /// Creates a failed result with [error].
  const factory Result.failure(E error) = Failure<T, E>;

  /// Returns `true` if this is a [Success].
  bool get isSuccess;

  /// Returns `true` if this is a [Failure].
  bool get isFailure;

  /// Returns the success value or `null` if this is a failure.
  T? get valueOrNull;

  /// Returns the error or `null` if this is a success.
  E? get errorOrNull;

  /// Returns the success value or throws the error if this is a failure.
  T get valueOrThrow;

  /// Returns the success value or the result of [defaultValue] if this is a failure.
  ///
  /// Example:
  /// ```dart
  /// final name = result.getOrElse(() => 'Unknown');
  /// ```
  T getOrElse(T Function() defaultValue);

  /// Transforms the result by applying [onSuccess] or [onFailure].
  ///
  /// Example:
  /// ```dart
  /// final message = result.fold(
  ///   onSuccess: (value) => 'Success: $value',
  ///   onFailure: (error) => 'Error: ${error.message}',
  /// );
  /// ```
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(E error) onFailure,
  });

  /// Executes [success] or [failure] callback based on the result type.
  ///
  /// Example:
  /// ```dart
  /// result.when(
  ///   success: (value) => print('Got: $value'),
  ///   failure: (error) => print('Error: ${error.message}'),
  /// );
  /// ```
  void when({
    required void Function(T value) success,
    required void Function(E error) failure,
  });

  /// Maps the success value using [transform].
  ///
  /// If this is a failure, returns the same failure.
  Result<R, E> map<R>(R Function(T value) transform);

  /// Maps the success value using an async [transform].
  Future<Result<R, E>> mapAsync<R>(Future<R> Function(T value) transform);

  /// Chains another Result-returning operation.
  ///
  /// If this is a success, applies [transform] to the value.
  /// If this is a failure, returns the same failure.
  ///
  /// Example:
  /// ```dart
  /// final result = userId.flatMap((id) => repository.getUser(id));
  /// ```
  Result<R, E> flatMap<R>(Result<R, E> Function(T value) transform);

  /// Async version of [flatMap].
  Future<Result<R, E>> flatMapAsync<R>(
      Future<Result<R, E>> Function(T value) transform);

  /// Transforms the error using [transform].
  ///
  /// If this is a success, returns the same success.
  /// If this is a failure, applies [transform] to create a new error.
  Result<T, F> mapError<F extends ApiException>(F Function(E error) transform);

  /// Recovers from a failure by providing a fallback value.
  ///
  /// If this is a success, returns the same success.
  /// If this is a failure, returns a success with the result of [recover].
  ///
  /// Example:
  /// ```dart
  /// final result = fetchUser().recover((error) => User.guest());
  /// ```
  Result<T, E> recover(T Function(E error) recover);
}

/// A successful result containing a [value].
final class Success<T, E extends ApiException> extends Result<T, E> {
  /// The success value.
  final T value;

  /// Creates a [Success] with [value].
  const Success(this.value) : super._();

  @override
  bool get isSuccess => true;

  @override
  bool get isFailure => false;

  @override
  T? get valueOrNull => value;

  @override
  E? get errorOrNull => null;

  @override
  T get valueOrThrow => value;

  @override
  T getOrElse(T Function() defaultValue) => value;

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(E error) onFailure,
  }) =>
      onSuccess(value);

  @override
  void when({
    required void Function(T value) success,
    required void Function(E error) failure,
  }) =>
      success(value);

  @override
  Result<R, E> map<R>(R Function(T value) transform) =>
      Result.success(transform(value));

  @override
  Future<Result<R, E>> mapAsync<R>(
          Future<R> Function(T value) transform) async =>
      Result.success(await transform(value));

  @override
  Result<R, E> flatMap<R>(Result<R, E> Function(T value) transform) =>
      transform(value);

  @override
  Future<Result<R, E>> flatMapAsync<R>(
          Future<Result<R, E>> Function(T value) transform) =>
      transform(value);

  @override
  Result<T, F> mapError<F extends ApiException>(
          F Function(E error) transform) =>
      Success<T, F>(value);

  @override
  Result<T, E> recover(T Function(E error) recover) => this;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T, E> &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Success($value)';
}

/// A failed result containing an [error].
final class Failure<T, E extends ApiException> extends Result<T, E> {
  /// The error.
  final E error;

  /// Creates a [Failure] with [error].
  const Failure(this.error) : super._();

  @override
  bool get isSuccess => false;

  @override
  bool get isFailure => true;

  @override
  T? get valueOrNull => null;

  @override
  E? get errorOrNull => error;

  @override
  T get valueOrThrow => throw error;

  @override
  T getOrElse(T Function() defaultValue) => defaultValue();

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(E error) onFailure,
  }) =>
      onFailure(error);

  @override
  void when({
    required void Function(T value) success,
    required void Function(E error) failure,
  }) =>
      failure(error);

  @override
  Result<R, E> map<R>(R Function(T value) transform) => Failure<R, E>(error);

  @override
  Future<Result<R, E>> mapAsync<R>(
          Future<R> Function(T value) transform) async =>
      Failure<R, E>(error);

  @override
  Result<R, E> flatMap<R>(Result<R, E> Function(T value) transform) =>
      Failure<R, E>(error);

  @override
  Future<Result<R, E>> flatMapAsync<R>(
          Future<Result<R, E>> Function(T value) transform) async =>
      Failure<R, E>(error);

  @override
  Result<T, F> mapError<F extends ApiException>(
          F Function(E error) transform) =>
      Failure<T, F>(transform(error));

  @override
  Result<T, E> recover(T Function(E error) recover) =>
      Success<T, E>(recover(error));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure<T, E> &&
          runtimeType == other.runtimeType &&
          error == other.error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Failure($error)';
}

/// Extension to convert a [Future] to a [Result].
///
/// Example:
/// ```dart
/// final result = await someAsyncOperation().getResult();
/// ```
extension ResultExtension<T> on Future<T> {
  /// Executes this future and wraps the result in a [Result].
  ///
  /// If the future completes successfully, returns [Success] with the value.
  /// If the future throws an [ApiException], returns [Failure] with the error.
  /// Other exceptions are rethrown.
  Future<Result<T, ApiException>> getResult() async {
    try {
      return Result.success(await this);
    } on ApiException catch (e) {
      return Result.failure(e);
    }
  }
}
