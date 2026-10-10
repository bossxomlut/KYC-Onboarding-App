import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'package:kyc_onboarding/features/auth/domain/repositories/auth_repository.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/logout.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/revalidate_session.dart';
import 'package:kyc_onboarding/features/auth/domain/usecases/restore_session.dart';
import 'package:kyc_onboarding/features/auth/presentation/bloc/auth_session_cubit.dart';

class FakeAuthRepository implements AuthRepository {
  Result<User?> nextRestore = const Success(null);
  Completer<Result<User?>>? delayedRestore;
  Result<void> nextLogout = const Success(null);
  Completer<Result<User>>? delayedRevalidation;
  Result<User> nextRevalidation = const Success(
    User(id: '1', email: 'demo@example.test', emailVerified: true),
  );
  int revalidationCalls = 0;
  @override
  Future<Result<User>> revalidateSession() async {
    revalidationCalls++;
    return delayedRevalidation == null
        ? nextRevalidation
        : await delayedRevalidation!.future;
  }

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
  test(
    'a new foreground cycle queues a fresh check and ignores old roles',
    () async {
      final firstResponse = Completer<Result<User>>();
      final nextResponse = Completer<Result<User>>();
      final repository = FakeAuthRepository()
        ..delayedRevalidation = firstResponse;
      final cubit = AuthSessionCubit(
        RestoreSession(repository),
        Logout(repository),
        revalidateSession: RevalidateSession(repository),
      )..signedIn(user);
      addTearDown(cubit.close);
      final publishedRoles = <UserRole>[];
      final subscription = cubit.stream.listen((state) {
        if (state is AuthAuthenticated) publishedRoles.add(state.user.role);
      });
      addTearDown(subscription.cancel);
      final scope = cubit.sessionScope;
      final first = cubit.revalidate();
      cubit.markForRevalidation();
      repository.delayedRevalidation = nextResponse;
      final second = cubit.revalidate();
      final repeated = cubit.revalidate();
      expect(repository.revalidationCalls, 1);
      const obsoleteRole = User(
        id: '1',
        email: 'demo@example.test',
        emailVerified: true,
        role: UserRole.reviewer,
      );
      firstResponse.complete(const Success(obsoleteRole));
      expect(await first, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(repository.revalidationCalls, 2);
      expect(publishedRoles, isNot(contains(UserRole.reviewer)));
      expect((cubit.state as AuthAuthenticated).user, user);
      expect(cubit.sessionScope, scope);
      nextResponse.complete(const Success(user));
      expect(await second, isTrue);
      expect(await repeated, isTrue);
      expect(cubit.state, const AuthAuthenticated(user));
      expect(cubit.sessionScope, scope);
    },
  );
  test(
    'a newer user update cannot be overwritten by a pending session check',
    () async {
      final pending = Completer<Result<User>>();
      final repository = FakeAuthRepository()..delayedRevalidation = pending;
      final cubit = AuthSessionCubit(
        RestoreSession(repository),
        Logout(repository),
        revalidateSession: RevalidateSession(repository),
      )..signedIn(user);
      addTearDown(cubit.close);
      final scope = cubit.sessionScope;
      final check = cubit.revalidate();
      const liveUser = User(
        id: '1',
        email: 'demo@example.test',
        emailVerified: true,
        role: UserRole.reviewer,
      );
      cubit.updateUser(liveUser);
      pending.complete(const Success(user));
      expect(await check, isFalse);
      expect((cubit.state as AuthAuthenticated).user, liveUser);
      expect((cubit.state as AuthAuthenticated).isRevalidating, isFalse);
      expect(repository.revalidationCalls, 1);
      expect(cubit.sessionScope, scope);
    },
  );
  test('revalidation keeps scope and coalesces concurrent checks', () async {
    final pending = Completer<Result<User>>();
    final repository = FakeAuthRepository()..delayedRevalidation = pending;
    final cubit = AuthSessionCubit(
      RestoreSession(repository),
      Logout(repository),
      revalidateSession: RevalidateSession(repository),
    )..signedIn(user);
    addTearDown(cubit.close);
    final scope = cubit.sessionScope;
    final first = cubit.revalidate();
    final second = cubit.revalidate();
    expect((cubit.state as AuthAuthenticated).isRevalidating, isTrue);
    expect(cubit.sessionScope, scope);
    expect(repository.revalidationCalls, 1);
    const updatedUser = User(
      id: '1',
      email: 'demo@example.test',
      emailVerified: true,
      role: UserRole.reviewer,
    );
    pending.complete(const Success(updatedUser));
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(cubit.state, const AuthAuthenticated(updatedUser));
    expect(cubit.sessionScope, scope);
  });
  test(
    'offline revalidation retains the current user and records error',
    () async {
      const offline = AppFailure(code: 'NETWORK_ERROR', message: 'Offline');
      final repository = FakeAuthRepository()
        ..nextRevalidation = const Failure(offline);
      final cubit = AuthSessionCubit(
        RestoreSession(repository),
        Logout(repository),
        revalidateSession: RevalidateSession(repository),
      )..signedIn(user);
      addTearDown(cubit.close);
      final scope = cubit.sessionScope;
      expect(await cubit.revalidate(), isFalse);
      final state = cubit.state as AuthAuthenticated;
      expect(state.user, user);
      expect(state.isRevalidating, isFalse);
      expect(state.revalidationError, offline);
      expect(cubit.sessionScope, scope);
      expect(repository.nextRestore, isA<Success<User?>>());
    },
  );
  test('revoked session revalidation signs out', () async {
    final repository = FakeAuthRepository()
      ..nextRevalidation = const Failure(
        AppFailure(code: 'SESSION_EXPIRED', message: 'Sign in again'),
      );
    final cubit = AuthSessionCubit(
      RestoreSession(repository),
      Logout(repository),
      revalidateSession: RevalidateSession(repository),
    )..signedIn(user);
    addTearDown(cubit.close);
    expect(await cubit.revalidate(), isFalse);
    expect(cubit.state, const AuthSignedOut());
    expect(cubit.sessionScope, isNull);
  });
  test('late revalidation cannot replace a new session', () async {
    final pending = Completer<Result<User>>();
    final repository = FakeAuthRepository()..delayedRevalidation = pending;
    final cubit = AuthSessionCubit(
      RestoreSession(repository),
      Logout(repository),
      revalidateSession: RevalidateSession(repository),
    )..signedIn(user);
    addTearDown(cubit.close);
    final operation = cubit.revalidate();
    const other = User(
      id: '2',
      email: 'other@example.test',
      emailVerified: true,
    );
    cubit.signedIn(other);
    pending.complete(const Success(user));
    expect(await operation, isFalse);
    expect(cubit.state, const AuthAuthenticated(other));
  });
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
