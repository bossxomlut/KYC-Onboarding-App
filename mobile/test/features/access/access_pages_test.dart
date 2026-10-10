import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/domain/result.dart';
import 'package:kyc_onboarding/features/access/domain/entities/access_entities.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/admin_page.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/reviewer_detail_page.dart';
import 'package:kyc_onboarding/features/access/domain/usecases/access_usecases.dart';
import 'package:kyc_onboarding/features/access/presentation/bloc/access_cubit.dart';
import 'package:kyc_onboarding/features/access/presentation/pages/access_page.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';
import 'access_cubit_test.dart';

void main() {
  testWidgets(
    'ordinary user submits a request and pending state prevents duplicates',
    (tester) async {
      final repo = FakeAccessRepository();
      final cubit = AccessCubit(AccessUseCases(repo));
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: MaterialApp(
            home: AccessPage(
              user: const User(
                id: 'u',
                email: 'u@example.test',
                emailVerified: true,
              ),
              onUserUpdated: (_) {},
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('request-reason')),
        'I can review identity documents.',
      );
      await tester.tap(find.byKey(const Key('request-reviewer')));
      await tester.pumpAndSettle();
      expect(find.text('Request status: pending'), findsOneWidget);
      expect(find.byKey(const Key('request-reviewer')), findsNothing);
      expect(repo.requestCount, 1);
      await cubit.close();
    },
  );
  testWidgets(
    'admin preserves super admin and creates only an email-verification account',
    (tester) async {
      final repo = _UiRepository();
      final cubit = AccessCubit(AccessUseCases(repo));
      await cubit.loadAdmin();
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: const MaterialApp(home: AdminPage()),
        ),
      );
      expect(find.text('Protected bootstrap account'), findsOneWidget);
      expect(find.text('Grant reviewer access'), findsOneWidget);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('admin-create-email')),
        'New@Example.test',
      );
      await tester.enterText(
        find.byKey(const Key('admin-create-password')),
        'FakePassword123',
      );
      await tester.ensureVisible(find.byKey(const Key('admin-create-account')));
      await tester.tap(find.byKey(const Key('admin-create-account')));
      await tester.pumpAndSettle();
      expect(repo.createdEmail, 'new@example.test');
      expect(repo.createdRole, UserRole.user);
      expect(
        find.text(
          'Account created. The user must verify the OTP sent to their email before signing in.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('admin-create-password')))
            .controller!
            .text,
        isEmpty,
      );
      await cubit.close();
    },
  );
  testWidgets(
    'access decision dialog safely closes before async request processing',
    (tester) async {
      final repo = _UiRepository()..hasPending = true;
      final cubit = AccessCubit(AccessUseCases(repo));
      await cubit.loadAdmin();
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: const MaterialApp(home: AdminPage()),
        ),
      );
      await tester.ensureVisible(find.text('Reject request'));
      await tester.tap(find.text('Reject request'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Response (optional)'),
        'Please explain your review experience.',
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.hasPending, isFalse);
      expect(find.text('No pending requests.'), findsOneWidget);
      await cubit.close();
    },
  );
  testWidgets(
    'review buttons remain disabled until both images load, then rejection requires a step',
    (tester) async {
      final repo = _UiRepository()..mediaUnavailable = true;
      final cubit = AccessCubit(AccessUseCases(repo));
      await cubit.loadDetail('u');
      final router = GoRouter(
        initialLocation: '/reviews/u',
        routes: [
          GoRoute(
            path: '/reviews/u',
            builder: (_, _) =>
                const ReviewerDetailPage(userId: 'u', actorId: 'r'),
          ),
          GoRoute(
            path: '/reviews',
            builder: (_, _) => const Scaffold(body: Text('Review queue')),
          ),
        ],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('review-approve')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('review-reject')))
            .onPressed,
        isNull,
      );
      repo.mediaUnavailable = false;
      await cubit.loadDetail('u');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('review-reject')));
      await tester.tap(find.byKey(const Key('review-reject')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('rejection-reason')),
        'Please retake the selfie.',
      );
      await tester.tap(find.text('Save rejection'));
      await tester.pumpAndSettle();
      expect(
        find.text('Give a reason and select at least one step.'),
        findsOneWidget,
      );
      expect(repo.decisions, 0);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Selfie'));
      await tester.tap(find.text('Save rejection'));
      await tester.pumpAndSettle();
      expect(repo.decisions, 1);
      expect(find.text('Review queue'), findsOneWidget);
      expect(cubit.state.detail, isNull);
      expect(cubit.state.media, isEmpty);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await cubit.close();
    },
  );
}

class _UiRepository extends FakeAccessRepository {
  String? createdEmail;
  UserRole? createdRole;
  bool mediaUnavailable = false;
  bool hasPending = false;
  @override
  Future<Result<PageResult<ManagedUser>>> users({int offset = 0}) async =>
      Success(
        PageResult(
          items: [
            ManagedUser(
              user: const User(
                id: 'a',
                email: 'admin@example.test',
                emailVerified: true,
                role: UserRole.superAdmin,
              ),
              createdAt: DateTime(2026),
            ),
            ManagedUser(
              user: const User(
                id: 'u',
                email: 'user@example.test',
                emailVerified: true,
              ),
              createdAt: DateTime(2026),
            ),
          ],
          total: 2,
          offset: offset,
        ),
      );
  @override
  Future<Result<PageResult<RoleRequest>>> requests({int offset = 0}) async =>
      Success(
        PageResult(
          items: hasPending
              ? [
                  RoleRequest(
                    id: 'request',
                    userId: 'u',
                    email: 'user@example.test',
                    status: RoleRequestStatus.pending,
                    reason: 'I review identity documents.',
                    createdAt: DateTime(2026),
                  ),
                ]
              : const [],
          total: hasPending ? 1 : 0,
          offset: offset,
        ),
      );
  @override
  Future<Result<RoleRequest>> decideRequest(
    String requestId,
    RoleRequestStatus decision, {
    String? reason,
  }) async {
    hasPending = false;
    return Success(
      RoleRequest(
        id: requestId,
        userId: 'u',
        email: 'user@example.test',
        status: decision,
        reason: 'I review identity documents.',
        createdAt: DateTime(2026),
        decisionReason: reason,
      ),
    );
  }

  @override
  Future<Result<User>> createUser({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    createdEmail = email;
    createdRole = role;
    return Success(
      User(id: 'new', email: email, emailVerified: false, role: role),
    );
  }

  @override
  Future<Result<ReviewDetail>> reviewDetail(String userId) async => Success(
    ReviewDetail(
      userId: userId,
      email: 'sample@example.test',
      profile: const KycProfile(
        id: 'p',
        status: KycStatus.pendingReview,
        nextStep: KycStep.result,
        document: KycMedia(id: 'd', mimeType: 'image/jpeg', size: 10),
        selfie: KycMedia(id: 's', mimeType: 'image/jpeg', size: 10),
      ),
    ),
  );
  @override
  Future<Result<Uint8List>> reviewMedia(String userId, MediaKind kind) async =>
      mediaUnavailable
      ? const Failure(
          AppFailure(code: 'SERVER_ERROR', message: 'Private image missing'),
        )
      : Success(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSu8AAAAASUVORK5CYII=',
          ),
        );
}
