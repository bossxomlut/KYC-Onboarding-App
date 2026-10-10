import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> clear();
  String? get accessToken;
}

/// Rotation must not overwrite a later login or resurrect a cleared session.
abstract interface class RotatingTokenStore implements TokenStore {
  Future<bool> rotateTokens({
    required String expectedRefreshToken,
    required String accessToken,
    required String refreshToken,
  });
}

final class SecureTokenStore implements RotatingTokenStore {
  SecureTokenStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'kyc.refresh-token.v1';
  String? _accessToken;
  Future<void> _pending = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  @override
  String? get accessToken => _accessToken;
  @override
  Future<String?> readRefreshToken() =>
      _serialize(() => _storage.read(key: _key));
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) => _serialize(() async {
    await _storage.write(key: _key, value: refreshToken);
    _accessToken = accessToken;
  });

  @override
  Future<bool> rotateTokens({
    required String expectedRefreshToken,
    required String accessToken,
    required String refreshToken,
  }) => _serialize(() async {
    if (await _storage.read(key: _key) != expectedRefreshToken) {
      return false;
    }
    await _storage.write(key: _key, value: refreshToken);
    _accessToken = accessToken;
    return true;
  });

  @override
  Future<void> clear() => _serialize(() async {
    await _storage.delete(key: _key);
    _accessToken = null;
  });
}
