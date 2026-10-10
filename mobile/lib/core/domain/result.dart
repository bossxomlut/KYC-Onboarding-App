sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class Failure<T> extends Result<T> {
  const Failure(this.error);
  final AppFailure error;
}

final class AppFailure {
  const AppFailure({required this.code, required this.message});
  final String code;
  final String message;
  bool get isNetwork => code == 'NETWORK_ERROR';

  @override
  bool operator ==(Object other) =>
      other is AppFailure && code == other.code && message == other.message;
  @override
  int get hashCode => Object.hash(code, message);
}
