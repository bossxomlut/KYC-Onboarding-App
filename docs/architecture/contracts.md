# Shared implementation contracts

## HTTP
Base `/api/v1`. JSON camelCase. Errors `{error:{code,message,requestId}}`. Bearer access tokens. Auth routes: register `{email,password}` -> `{user,nextStep:"VERIFY_EMAIL"}`; email/verify `{email,code}` and login `{email,password}` and refresh `{refreshToken}` -> `{user,accessToken,refreshToken,expiresIn:900}`. me -> `{user}`. email/resend and password/forgot -> `{message}`. password/reset `{token,newPassword}`. logout `{refreshToken}`.

## KYC
GET `/kyc` -> `{profile: {...}}`; PUT `/kyc/personal-details` body `{fullName,dateOfBirth,nationality,address,documentNumber}`; POST `/kyc/media/:kind` multipart field `file`, optional `captureId` (16–128 URL-safe characters) to correlate/retry interrupted captures; document also `documentType` (`passport`,`national_id`,`driving_licence`), kinds `document`, `selfie`; GET `/kyc/media/:kind` authenticated bytes. POST `/kyc/submit`, POST `/kyc/resubmit` -> `{profile}`.

Profile: `{id,status,nextStep,personalDetails,document,selfie,rejectionReason,requiredSteps,submittedAt,updatedAt}`. Status `not_started`, `in_progress`, `pending_review`, `verified`, `rejected`. Step `personal_details`, `document`, `selfie`, `review`, `result`. PersonalDetails nullable uses fields above. Media nullable `{id,mimeType,size,documentType?,captureId?}`. On resubmit clear required rejected assets, preserve accepted data, transition in_progress and derive nextStep. Updates disallowed when pending_review/verified/rejected until resubmit. Review results set using backend CLI, not a public admin endpoint.

## Flutter shared contracts
Paths use `lib/core`, `lib/features`, `lib/app`. `core/domain/result.dart`: sealed `Result<T>` with `Success<T>(value)`, `Failure<T>(AppFailure error)`; `AppFailure` fields code/message and getter isNetwork. Pure Dart.
`core/network/api_client.dart`: ApiClient(Dio dio), methods get/post/put returning decoded `Map<String,dynamic>`, upload(path,filePath,{fields}), bytes(path), and public Dio get dio. Shared network/auth data layers implement token storage and retry.
`core/security/token_store.dart`: TokenStore interface `Future<String?> readRefreshToken()`, `Future<void> saveTokens({required String accessToken,required String refreshToken})`, `Future<void> clear()`, `String? get accessToken`; SecureTokenStore implementation. No persistence of PII in plaintext.
AuthSessionCubit is app-scoped; KycCubit is authenticated-flow scoped. Root DI/router may compose both without feature flow-to-flow imports. Auth repository exposes use cases consumed by auth cubits. KYC repository/use cases consume ApiClient.
