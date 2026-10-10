import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../../core/network/api_client.dart';
import '../../core/network/bearer_token_interceptor.dart';
import '../../core/security/token_store.dart';
import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/data/session_refresher.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login.dart';
import '../../features/auth/domain/usecases/logout.dart';
import '../../features/auth/domain/usecases/register.dart';
import '../../features/auth/domain/usecases/request_password_reset.dart';
import '../../features/auth/domain/usecases/resend_verification_code.dart';
import '../../features/auth/domain/usecases/reset_password.dart';
import '../../features/auth/domain/usecases/restore_session.dart';
import '../../features/auth/domain/usecases/verify_email.dart';
import '../../features/auth/presentation/bloc/auth_session_cubit.dart';
import '../../features/auth/presentation/bloc/login_cubit.dart';
import '../../features/auth/presentation/bloc/register_cubit.dart';
import '../../features/auth/presentation/bloc/email_verification_cubit.dart';
import '../../features/auth/presentation/bloc/password_reset_cubit.dart';
import '../../features/access/data/datasources/access_remote_datasource.dart';
import '../../features/access/data/repositories/access_repository_impl.dart';
import '../../features/access/domain/repositories/access_repository.dart';
import '../../features/access/domain/usecases/access_usecases.dart';
import '../../features/access/presentation/bloc/access_cubit.dart';
import '../../features/kyc/data/datasources/camera_datasource.dart';
import '../../features/kyc/data/datasources/kyc_remote_datasource.dart';
import '../../features/kyc/data/repositories/kyc_repository_impl.dart';
import '../../features/kyc/domain/repositories/kyc_repository.dart';
import '../../features/kyc/domain/usecases/kyc_usecases.dart';
import '../../features/kyc/presentation/bloc/kyc_cubit.dart';
import '../../features/kyc_history/data/datasources/kyc_history_remote_datasource.dart';
import '../../features/kyc_history/data/repositories/kyc_history_repository_impl.dart';
import '../../features/kyc_history/domain/repositories/kyc_history_repository.dart';
import '../../features/kyc_history/domain/usecases/kyc_history_usecases.dart';
import '../../features/kyc_history/presentation/bloc/kyc_history_cubit.dart';

/// Composition root; a fresh container lets tests replace platform capture while
/// still exercising the production HTTP repositories against the real API.
GetIt configureDependencies({
  String? baseUrl,
  TokenStore? tokens,
  CameraDataSource? camera,
}) {
  final di = GetIt.asNewInstance();
  const configured = String.fromEnvironment('API_BASE_URL');
  final url =
      baseUrl ??
      (configured.isNotEmpty
          ? configured
          : 'http://${Platform.isAndroid ? '10.0.2.2' : '127.0.0.1'}:3000/api/v1');
  final uri = Uri.parse(url);
  if (uri.scheme != 'https' && !kDebugMode) {
    throw StateError('Release builds require an HTTPS API_BASE_URL.');
  }
  final dio = Dio(
    BaseOptions(
      baseUrl: url,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
    ),
  );
  final store =
      tokens ??
      SecureTokenStore(
        const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.unlocked_this_device,
          ),
        ),
      );
  final api = ApiClient(dio);
  final remote = AuthRemoteDataSource(api);
  final refresher = SessionRefresher(remote, store);
  final auth = AuthRepositoryImpl(remote, store, refresher);
  di.registerSingleton<Dio>(dio, dispose: (value) => value.close());
  di.registerSingleton<ApiClient>(api);
  di.registerSingleton<TokenStore>(store);
  di.registerSingleton<AuthRepository>(auth);
  di.registerSingleton<SessionRefresher>(refresher);
  di.registerFactory(
    () => AuthSessionCubit(RestoreSession(auth), Logout(auth)),
  );
  di.registerFactory(() => LoginCubit(Login(auth)));
  di.registerFactory(() => RegisterCubit(Register(auth)));
  di.registerFactory(
    () =>
        EmailVerificationCubit(VerifyEmail(auth), ResendVerificationCode(auth)),
  );
  di.registerFactory(
    () => PasswordResetCubit(RequestPasswordReset(auth), ResetPassword(auth)),
  );
  final access = AccessRepositoryImpl(AccessRemoteDataSource(api));
  di.registerSingleton<AccessRepository>(access);
  di.registerFactory(() => AccessCubit(AccessUseCases(access)));
  final history = KycHistoryRepositoryImpl(KycHistoryRemoteDataSource(api));
  di.registerSingleton<KycHistoryRepository>(history);
  di.registerFactory(
    () => KycHistoryCubit(
      loadHistory: LoadKycHistory(history),
      loadMedia: LoadKycHistoryMedia(history),
    ),
  );
  final kyc = KycRepositoryImpl(
    KycRemoteDataSource(api),
    camera ?? ImagePickerCameraDataSource(),
  );
  di.registerSingleton<KycRepository>(kyc);
  di.registerFactory(
    () => KycCubit(
      loadKyc: LoadKyc(kyc),
      savePersonalDetails: SavePersonalDetails(kyc),
      captureMedia: CaptureMedia(kyc),
      uploadMedia: UploadMedia(kyc),
      loadPrivateMedia: LoadPrivateMedia(kyc),
      submitKyc: SubmitKyc(kyc),
      resubmitKyc: ResubmitKyc(kyc),
      recoverCapture: RecoverCapture(kyc),
      discardLocalMedia: DiscardLocalMedia(kyc),
    ),
  );
  return di;
}

void connectSession(GetIt di, AuthSessionCubit session) {
  di<Dio>().interceptors.removeWhere(
    (interceptor) => interceptor is BearerTokenInterceptor,
  );
  di<Dio>().interceptors.add(
    BearerTokenInterceptor(
      di<Dio>(),
      di<TokenStore>(),
      refresh: di<SessionRefresher>().refreshCredentials,
      invalidate: () async {
        final scope = session.sessionScope;
        await di<TokenStore>().clear();
        if (scope == session.sessionScope) await session.sessionInvalidated();
      },
      sessionScope: () => session.sessionScope,
    ),
  );
}
