import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/security/token_store.dart';

class _DelayedDeleteStorage extends FlutterSecureStorage {
  final reachedDelete = Completer<void>();
  final releaseDelete = Completer<void>();
  int writes = 0;

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reachedDelete.complete();
    await releaseDelete.future;
    await super.delete(key: key);
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes++;
    await super.write(key: key, value: value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('conditional clearing refuses to delete a newer saved login', () async {
    final tokens = SecureTokenStore(const FlutterSecureStorage());
    await tokens.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );
    final saving = tokens.saveTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    );
    final clearing = tokens.clearIfUnchanged(
      expectedRefreshToken: 'old-refresh',
    );
    await saving;
    expect(await clearing, isFalse);
    expect(await tokens.readRefreshToken(), 'new-refresh');
    expect(tokens.accessToken, 'new-access');
  });

  test(
    'conditional clearing and saving are one serialized storage sequence',
    () async {
      final storage = _DelayedDeleteStorage();
      final tokens = SecureTokenStore(storage);
      await tokens.saveTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
      );
      final clearing = tokens.clearIfUnchanged(
        expectedRefreshToken: 'old-refresh',
      );
      await storage.reachedDelete.future;
      final saving = tokens.saveTokens(
        accessToken: 'new-access',
        refreshToken: 'new-refresh',
      );
      await Future<void>.delayed(Duration.zero);
      try {
        expect(storage.writes, 1);
      } finally {
        storage.releaseDelete.complete();
        await saving;
        expect(await clearing, isTrue);
      }
      expect(await tokens.readRefreshToken(), 'new-refresh');
      expect(tokens.accessToken, 'new-access');
    },
  );

  test('a reset started signed out cannot delete a later login', () async {
    final tokens = SecureTokenStore(const FlutterSecureStorage());
    await tokens.saveTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    );
    final cleared = await tokens.clearIfUnchanged(expectedRefreshToken: null);
    expect(cleared, isFalse);
    expect(await tokens.readRefreshToken(), 'new-refresh');
    expect(tokens.accessToken, 'new-access');
  });

  test('atomic rotation refuses to replace a newer login', () async {
    final tokens = SecureTokenStore(const FlutterSecureStorage());
    await tokens.saveTokens(
      accessToken: 'login-access',
      refreshToken: 'login-refresh',
    );
    final saved = await tokens.rotateTokens(
      expectedRefreshToken: 'previous-refresh',
      accessToken: 'stale-access',
      refreshToken: 'stale-refresh',
    );
    expect(saved, isFalse);
    expect(await tokens.readRefreshToken(), 'login-refresh');
    expect(tokens.accessToken, 'login-access');
  });

  test(
    'rotation and logout are serialized so logout leaves no tokens',
    () async {
      final tokens = SecureTokenStore(const FlutterSecureStorage());
      await tokens.saveTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
      );
      final rotation = tokens.rotateTokens(
        expectedRefreshToken: 'old-refresh',
        accessToken: 'new-access',
        refreshToken: 'new-refresh',
      );
      final clearing = tokens.clear();
      await Future.wait<Object?>([rotation, clearing]);
      expect(await tokens.readRefreshToken(), isNull);
      expect(tokens.accessToken, isNull);
    },
  );
}
