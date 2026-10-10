import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/auth/domain/repositories/auth_repository.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/logout.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/restore_session.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/auth_session_cubit.dart';

class FakeAuthRepository implements AuthRepository {
  Result<User?> nextRestore = const Success(null);
  Completer<Result<User?>>? delayedRestore;
  Result<void> nextLogout = const Success(null);
  @override
  Future<Result<User?>> restoreSession() async =>
      delayedRestore == null ? nextRestore : await delayedRestore!.future;
  @override
  Future<Result<void>> logout() async => nextLogout;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const user = User(id: '1', email: 'demo@example.test', emailVerified: true);
  test('late startup response cannot replace a newer session', () async {
    const otherUser = User(
      id: '2',
      email: 'other@example.test',
      emailVerified: true,
    );
    final pending = Completer<Result<User?>>();
    final repository = FakeAuthRepository()..delayedRestore = pending;
    final cubit = AuthSessionCubit(
      RestoreSession(repository),
      Logout(repository),
    );
    final restoration = cubit.restore();
    cubit.signedIn(otherUser);
    pending.complete(const Success(user));
    await restoration;
    expect(cubit.state, const AuthAuthenticated(otherUser));
    await cubit.close();
  });
  test('network restore is recoverable by retry', () async {
    final repository = FakeAuthRepository()
      ..nextRestore = const Failure(
        AppFailure(code: 'NETWORK_ERROR', message: 'Offline'),
      );
    final cubit = AuthSessionCubit(
      RestoreSession(repository),
      Logout(repository),
    );
    await cubit.restore();
    expect(cubit.state, isA<AuthConnectionFailure>());
    repository.nextRestore = const Success(user);
    await cubit.restore();
    expect(cubit.state, const AuthAuthenticated(user));
    await cubit.close();
  });
  test('invalid restore signs out and offline logout preserves user', () async {
    final repository = FakeAuthRepository();
    final cubit = AuthSessionCubit(
      RestoreSession(repository),
      Logout(repository),
    );
    await cubit.restore();
    expect(cubit.state, isA<AuthSignedOut>());
    cubit.signedIn(user);
    repository.nextLogout = const Failure(
      AppFailure(code: 'NETWORK_ERROR', message: 'Offline'),
    );
    await cubit.signOut();
    expect(cubit.state, isA<AuthAuthenticated>());
    expect((cubit.state as AuthAuthenticated).error?.isNetwork, isTrue);
    expect((cubit.state as AuthAuthenticated).user, user);
    await cubit.close();
  });
}
