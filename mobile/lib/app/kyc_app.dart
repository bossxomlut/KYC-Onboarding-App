import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/navigation/current_route.dart';
import '../features/auth/presentation/bloc/auth_session_cubit.dart';
import '../features/auth/presentation/bloc/login_cubit.dart';
import '../features/auth/presentation/bloc/register_cubit.dart';
import '../features/auth/presentation/bloc/email_verification_cubit.dart';
import '../features/auth/presentation/bloc/password_reset_cubit.dart';
import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/pages/register_page.dart';
import '../features/auth/presentation/pages/verify_email_page.dart';
import '../features/auth/presentation/pages/forgot_password_page.dart';
import '../features/auth/presentation/pages/reset_password_page.dart';
import '../features/auth/domain/entities/user.dart';
import '../features/access/presentation/bloc/access_cubit.dart';
import '../features/access/presentation/pages/access_page.dart';
import '../features/access/presentation/pages/admin_page.dart';
import '../features/access/presentation/pages/admin_home_page.dart';
import '../features/access/presentation/pages/reviewer_queue_page.dart';
import '../features/access/presentation/pages/reviewer_detail_page.dart';
import '../features/kyc/domain/entities/kyc_profile.dart';
import '../features/kyc/presentation/bloc/kyc_cubit.dart';
import '../features/kyc/presentation/pages/home_page.dart';
import '../features/kyc/presentation/pages/personal_details_page.dart';
import '../features/kyc/presentation/pages/capture_page.dart';
import '../features/kyc/presentation/widgets/capture_camera_configuration.dart';
import '../features/kyc/presentation/pages/review_page.dart';
import '../features/kyc/presentation/pages/verification_page.dart';
import '../features/kyc_history/presentation/bloc/kyc_history_cubit.dart';
import '../features/kyc_history/presentation/pages/kyc_history_page.dart';
import 'di/dependencies.dart';
import 'lifecycle/foreground_refresh.dart';
import 'router/back_to_home_scope.dart';
import 'router/route_policy.dart';

class KycApp extends StatefulWidget {
  const KycApp({required this.dependencies, this.initialLocation, super.key});
  final GetIt dependencies;
  final String? initialLocation;
  @override
  State<KycApp> createState() => _KycAppState();
}

class _KycAppState extends State<KycApp> with WidgetsBindingObserver {
  final _foreground = ForegroundRefreshController();
  late final AuthSessionCubit _session;
  late final _RouterRefresh _refresh;
  late final GoRouter _router;
  @override
  void initState() {
    super.initState();
    final di = widget.dependencies;
    _session = di<AuthSessionCubit>();
    connectSession(di, _session);
    _refresh = _RouterRefresh(
      _session.stream,
      redirectCurrentRoute: () {
        if (_router.routerDelegate.currentConfiguration.isEmpty) return false;
        final redirect = _sessionRedirect(_router.state.uri.path);
        if (redirect == null) return false;
        // Router refresh restores the declarative base URI. Check the pushed
        // page too when live session/role changes revoke its access.
        _router.go(redirect);
        return true;
      },
    );
    _router = GoRouter(
      initialLocation: widget.initialLocation,
      refreshListenable: _refresh,
      redirect: (context, state) => _sessionRedirect(state.uri.path),
      routes: [
        GoRoute(
          path: '/session',
          builder: (context, state) => const _SessionPage(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => BlocProvider(
            create: (_) => di<LoginCubit>(),
            child: LoginPage(
              onSignedIn: _session.signedIn,
              onVerificationRequired: _session.verificationRequired,
            ),
          ),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => BlocProvider(
            create: (_) => di<RegisterCubit>(),
            child: RegisterPage(
              onVerificationRequired: _session.verificationRequired,
            ),
          ),
        ),
        GoRoute(
          path: '/verify-email',
          builder: (context, state) {
            final auth = _session.state;
            final email = auth is AuthEmailVerificationRequired
                ? auth.email
                : state.uri.queryParameters['email'] ?? '';
            return BlocProvider(
              create: (_) {
                final cubit = di<EmailVerificationCubit>();
                if (auth is AuthEmailVerificationRequired) {
                  cubit.startCooldown();
                }
                return cubit;
              },
              child: RouteForegroundRefresh(
                location: state.uri.path,
                onResume: (context) async =>
                    context.read<EmailVerificationCubit>().reconcileCooldown(),
                child: VerifyEmailPage(
                  email: email,
                  onSignedIn: _session.signedIn,
                  onChangeEmail: () {
                    _session.cancelVerification();
                    context.go('/register');
                  },
                ),
              ),
            );
          },
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => BlocProvider(
            create: (_) => di<PasswordResetCubit>(),
            child: const ForgotPasswordPage(),
          ),
        ),
        GoRoute(
          path: '/reset-password',
          builder: (context, state) {
            return BlocProvider(
              create: (_) => di<PasswordResetCubit>(),
              child: ResetPasswordPage(
                token: state.uri.queryParameters['token'] ?? '',
                onPasswordResetStarted: () {
                  final scope = _session.sessionScope;
                  return () async {
                    if (scope == _session.sessionScope) {
                      await _session.sessionInvalidated();
                    }
                  };
                },
              ),
            );
          },
        ),
        GoRoute(
          path: '/access',
          builder: (context, state) => BackToHomeScope(
            child: BlocProvider(
              create: (_) => di<AccessCubit>()..loadAccess(),
              child: _accessForegroundPage(
                state,
                refresh: (cubit) => cubit.loadAccess(),
                child: AccessPage(
                  user: (_session.state as AuthAuthenticated).user,
                  onUserUpdated: _session.updateUser,
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/admin',
          builder: (context, state) => BackToHomeScope(
            child: BlocProvider(
              create: (_) => di<AccessCubit>()..loadAdmin(),
              child: _accessForegroundPage(
                state,
                refresh: (cubit) => cubit.loadAdmin(
                  offset: cubit.state.users?.offset ?? 0,
                  requestOffset: cubit.state.requests?.offset ?? 0,
                ),
                child: const AdminPage(),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/reviews',
          builder: (context, state) => BackToHomeScope(
            child: BlocProvider(
              create: (_) => di<AccessCubit>()..loadQueue(),
              child: _accessForegroundPage(
                state,
                refresh: (cubit) => cubit.loadQueue(),
                child: ReviewerQueuePage(
                  actorId: (_session.state as AuthAuthenticated).user.id,
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/reviews/:userId',
          builder: (context, state) {
            final userId = state.pathParameters['userId']!;
            return BackToHomeScope(
              child: BlocProvider(
                create: (_) => di<AccessCubit>()..loadDetail(userId),
                child: _accessForegroundPage(
                  state,
                  refresh: (cubit) => cubit.loadDetail(userId),
                  child: ReviewerDetailPage(
                    userId: userId,
                    actorId: (_session.state as AuthAuthenticated).user.id,
                  ),
                ),
              ),
            );
          },
        ),
        GoRoute(
          path: '/kyc/history',
          builder: (context, state) => BackToHomeScope(
            child: BlocProvider(
              create: (_) => di<KycHistoryCubit>(),
              child: _historyForegroundPage(state, const KycHistoryPage()),
            ),
          ),
        ),
        GoRoute(
          path: '/reviews/:userId/history',
          builder: (context, state) => BackToHomeScope(
            child: BlocProvider(
              key: ValueKey(state.pathParameters['userId']),
              create: (_) => di<KycHistoryCubit>(),
              child: _historyForegroundPage(
                state,
                KycHistoryPage(
                  reviewerUserId: state.pathParameters['userId']!,
                  fromReviewQueue: state.uri.queryParameters['from'] == 'queue',
                ),
              ),
            ),
          ),
        ),
        ShellRoute(
          builder: (context, state, child) {
            final auth = _session.state;
            if (auth is! AuthAuthenticated) return const _SessionPage();
            if (auth.user.canManageUsers) return child;
            return BlocProvider(
              key: ValueKey(auth.user.id),
              create: (_) => di<KycCubit>()..load(),
              child: child,
            );
          },
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) {
                final user = (_session.state as AuthAuthenticated).user;
                if (user.canManageUsers) {
                  return BlocBuilder<AuthSessionCubit, AuthSessionState>(
                    builder: (context, auth) {
                      if (auth is! AuthAuthenticated) {
                        return const _SessionPage();
                      }
                      return _AuthenticatedForegroundRefresh(
                        location: state.uri.path,
                        child: AdminHomePage(
                          user: auth.user,
                          isSigningOut: auth.isSigningOut,
                          error: auth.error,
                          onLogout: () async {
                            await _session.signOut();
                          },
                        ),
                      );
                    },
                  );
                }
                return _kycPage(
                  state,
                  HomePage(
                    email: user.email,
                    canReview: user.canReview,
                    onLogout: () async {
                      final flow = context.read<KycCubit>();
                      await _session.signOut();
                      if (_session.state is AuthSignedOut) {
                        await flow.discardLocalMedia();
                      }
                      if (context.mounted) {
                        final auth = _session.state;
                        if (auth is AuthAuthenticated && auth.error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(auth.error!.message)),
                          );
                        }
                      }
                    },
                  ),
                );
              },
            ),
            GoRoute(
              path: '/kyc/details',
              builder: (context, state) =>
                  _kycPage(state, const PersonalDetailsPage()),
            ),
            GoRoute(
              path: '/kyc/document',
              builder: (context, state) => _kycPage(
                state,
                CapturePage(
                  kind: MediaKind.document,
                  camera: di.isRegistered<CaptureCameraConfiguration>()
                      ? di<CaptureCameraConfiguration>()
                      : null,
                ),
              ),
            ),
            GoRoute(
              path: '/kyc/selfie',
              builder: (context, state) => _kycPage(
                state,
                CapturePage(
                  kind: MediaKind.selfie,
                  camera: di.isRegistered<CaptureCameraConfiguration>()
                      ? di<CaptureCameraConfiguration>()
                      : null,
                ),
              ),
            ),
            GoRoute(
              path: '/kyc/review',
              builder: (context, state) => _kycPage(state, const ReviewPage()),
            ),
            GoRoute(
              path: '/kyc/status',
              builder: (context, state) =>
                  _kycPage(state, const VerificationPage()),
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Page unavailable')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Go home'),
          ),
        ),
      ),
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_session.restore());
  }

  String? _sessionRedirect(String location) {
    final auth = _session.state;
    final access = switch (auth) {
      AuthInitializing() => SessionAccess.initializing,
      AuthConnectionFailure() => SessionAccess.connectionFailure,
      AuthSignedOut() => SessionAccess.signedOut,
      AuthEmailVerificationRequired() => SessionAccess.verifyEmail,
      AuthAuthenticated() => SessionAccess.authenticated,
    };
    return RoutePolicy.redirect(
      access: access,
      location: location,
      role: auth is AuthAuthenticated ? auth.user.role : UserRole.user,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_foreground.isBackgrounded &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      _session.markForRevalidation();
    }
    _foreground.handle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foreground.dispose();
    _router.dispose();
    _refresh.dispose();
    unawaited(_session.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ForegroundRefreshScope(
    controller: _foreground,
    child: BlocProvider.value(
      value: _session,
      child: MaterialApp.router(
        title: 'Identity',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
        builder: (context, child) =>
            BlocBuilder<AuthSessionCubit, AuthSessionState>(
              builder: (context, state) => Stack(
                children: [
                  child!,
                  if (state is AuthAuthenticated &&
                      state.revalidationError != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: SafeArea(
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(state.revalidationError!.message),
                                ),
                                TextButton(
                                  key: const Key('retry-foreground'),
                                  onPressed: state.isRevalidating
                                      ? null
                                      : _foreground.retry,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      ),
    ),
  );
}

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(
    Stream<AuthSessionState> stream, {
    required bool Function() redirectCurrentRoute,
  }) {
    _subscription = stream.listen((_) {
      if (!redirectCurrentRoute()) notifyListeners();
    });
  }
  late final StreamSubscription<AuthSessionState> _subscription;
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

Widget _kycPage(GoRouterState state, Widget child) => BackToHomeScope(
  enabled: state.uri.path != '/',
  child: _AuthenticatedForegroundRefresh(
    location: state.uri.path,
    prepare: (context) => context.read<KycCubit>().prepareForResume(),
    refresh: (context) => context.read<KycCubit>().refresh(),
    child: _KycFlowGuard(location: state.uri.path, child: child),
  ),
);

Widget _accessForegroundPage(
  GoRouterState state, {
  required Future<void> Function(AccessCubit) refresh,
  required Widget child,
}) => _AuthenticatedForegroundRefresh(
  location: state.uri.path,
  prepare: (context) => context.read<AccessCubit>().prepareForResume(),
  refresh: (context) => refresh(context.read<AccessCubit>()),
  child: child,
);

Widget _historyForegroundPage(GoRouterState state, Widget child) =>
    _AuthenticatedForegroundRefresh(
      location: state.uri.path,
      refresh: (context) => context.read<KycHistoryCubit>().refresh(),
      child: child,
    );

class _AuthenticatedForegroundRefresh extends StatelessWidget {
  const _AuthenticatedForegroundRefresh({
    required this.location,
    required this.child,
    this.prepare,
    this.refresh,
  });
  final String location;
  final Widget child;
  final void Function(BuildContext)? prepare;
  final Future<void> Function(BuildContext)? refresh;
  @override
  Widget build(BuildContext context) => RouteForegroundRefresh(
    location: location,
    onBackground: prepare,
    onResume: (context) async {
      final controller = ForegroundRefreshScope.of(context);
      final session = context.read<AuthSessionCubit>();
      final scope = session.sessionScope;
      final generation = controller.generation;
      final confirmed = await session.revalidate();
      if (confirmed &&
          context.mounted &&
          !controller.isBackgrounded &&
          generation == controller.generation &&
          scope == session.sessionScope &&
          isCurrentRoute(context)) {
        await refresh?.call(context);
      }
    },
    child: child,
  );
}

class _SessionPage extends StatelessWidget {
  const _SessionPage();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: BlocBuilder<AuthSessionCubit, AuthSessionState>(
            builder: (context, state) {
              if (state is! AuthConnectionFailure) {
                return const CircularProgressIndicator();
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    'Let’s reconnect',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(state.error.message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: context.read<AuthSessionCubit>().restore,
                    child: const Text('Retry connection'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// Guards one page while the authenticated shell owns the flow's Cubit.
class _KycFlowGuard extends StatefulWidget {
  const _KycFlowGuard({required this.location, required this.child});
  final String location;
  final Widget child;
  @override
  State<_KycFlowGuard> createState() => _KycFlowGuardState();
}

class _KycFlowGuardState extends State<_KycFlowGuard> {
  String? _redirect(KycProfile profile) => RoutePolicy.redirect(
    access: SessionAccess.authenticated,
    location: widget.location,
    kycStatus: switch (profile.status) {
      KycStatus.notStarted => 'not_started',
      KycStatus.inProgress => 'in_progress',
      KycStatus.pendingReview => 'pending_review',
      KycStatus.verified => 'verified',
      KycStatus.rejected => 'rejected',
    },
    nextStep: switch (profile.nextStep) {
      KycStep.personalDetails => 'personal_details',
      KycStep.document => 'document',
      KycStep.selfie => 'selfie',
      KycStep.review => 'review',
      KycStep.result => 'result',
    },
  );
  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
    builder: (context, state) {
      if (state.profile == null) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: state.error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            state.error!.message,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: context.read<KycCubit>().load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      }
      final redirect = _redirect(state.profile!);
      if (redirect != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && isCurrentRoute(context)) {
            context.pushReplacement(redirect);
          }
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return widget.child;
    },
  );
}
