import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/security/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('atomic rotation refuses to replace a newer login', () async {
    final tokens = SecureTokenStore(const FlutterSecureStorage());
    await tokens.saveTokens(
        accessToken: 'login-access', refreshToken: 'login-refresh');
    final saved = await tokens.rotateTokens(
        expectedRefreshToken: 'previous-refresh',
        accessToken: 'stale-access',
        refreshToken: 'stale-refresh');
    expect(saved, isFalse);
    expect(await tokens.readRefreshToken(), 'login-refresh');
    expect(tokens.accessToken, 'login-access');
  });

  test('rotation and logout are serialized so logout leaves no tokens',
      () async {
    final tokens = SecureTokenStore(const FlutterSecureStorage());
    await tokens.saveTokens(
        accessToken: 'old-access', refreshToken: 'old-refresh');
    final rotation = tokens.rotateTokens(
        expectedRefreshToken: 'old-refresh',
        accessToken: 'new-access',
        refreshToken: 'new-refresh');
    final clearing = tokens.clear();
    await Future.wait<Object?>([rotation, clearing]);
    expect(await tokens.readRefreshToken(), isNull);
    expect(tokens.accessToken, isNull);
  });
}
