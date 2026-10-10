import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/logout.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/restore_session.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/auth_session_cubit.dart';
import '../auth/presentation/auth_session_cubit_test.dart'
    show FakeAuthRepository;

class _DelayedLogoutRepository extends FakeAuthRepository {
  final logoutCompleter = Completer<Result<void>>();
  @override
  Future<Result<void>> logout() => logoutCompleter.future;
}

void main() {
  test(
    'live role update preserves logout busy flag and current session scope',
    () async {
      const initial = User(
        id: 'u',
        email: 'user@example.test',
        emailVerified: true,
      );
      const updated = User(
        id: 'u',
        email: 'user@example.test',
        emailVerified: true,
        role: UserRole.reviewer,
      );
      final repository = _DelayedLogoutRepository();
      final cubit = AuthSessionCubit(
        RestoreSession(repository),
        Logout(repository),
      );
      cubit.signedIn(initial);
      final scope = cubit.sessionScope;
      final logout = cubit.signOut();
      cubit.updateUser(updated);
      expect((cubit.state as AuthAuthenticated).isSigningOut, isTrue);
      expect(cubit.sessionScope, scope);
      expect(await cubit.signOut(), isFalse);
      repository.logoutCompleter.complete(
        const Failure(AppFailure(code: 'NETWORK_ERROR', message: 'Offline')),
      );
      await logout;
      expect((cubit.state as AuthAuthenticated).user, updated);
      expect((cubit.state as AuthAuthenticated).error?.isNetwork, isTrue);
      await cubit.close();
    },
  );
}
