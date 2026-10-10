# Shared implementation contracts

## HTTP

Base `/api/v1`. JSON camelCase. Errors `{error:{code,message,requestId}}`. Bearer access tokens. Auth routes: register `{email,password}` -> `{user,nextStep:"VERIFY_EMAIL"}`; email/verify `{email,code}` and login `{email,password}` and refresh `{refreshToken}` -> `{user,accessToken,refreshToken,expiresIn:900}`. me -> `{user}`. Public users include `{id,email,emailVerified,role}`; role is `user`, `reviewer` or `super_admin`, read live from the database. email/resend and password/forgot -> `{message}`. password/reset `{token,newPassword}`. logout `{refreshToken}`.

Login with valid credentials for an unverified email creates and attempts delivery of a verification OTP before returning `403 EMAIL_NOT_VERIFIED`; the client opens email verification without a manual resend. Login and resend share the 30-second OTP creation cooldown. Failed mail delivery remains in the encrypted outbox for retry. Invalid credentials, disabled users, and verified users do not trigger verification mail.

## KYC

GET `/kyc` -> `{profile: {...}}`; PUT `/kyc/personal-details` body `{fullName,dateOfBirth,nationality,address,documentNumber}`; POST `/kyc/media/:kind` multipart field `file`, optional `captureId` (16–128 URL-safe characters) to correlate/retry interrupted captures; document also `documentType` (`passport`,`national_id`,`driving_licence`), kinds `document`, `selfie`; GET `/kyc/media/:kind` authenticated bytes. POST `/kyc/submit`, POST `/kyc/resubmit` -> `{profile}`.

Profile: `{id,status,nextStep,personalDetails,document,selfie,rejectionReason,requiredSteps,submittedAt,updatedAt}`. Status `not_started`, `in_progress`, `pending_review`, `verified`, `rejected`. Step `personal_details`, `document`, `selfie`, `review`, `result`. PersonalDetails nullable uses fields above. Media nullable `{id,mimeType,size,documentType?,captureId?}`. On resubmit clear required rejected assets, preserve accepted data, transition in_progress and derive nextStep. Updates disallowed when pending_review/verified/rejected until resubmit. Review results are set by authenticated reviewer/super_admin accounts through `/reviews/:userId/decision`; self-review is forbidden and every new decision records its actor.

## Flutter shared contracts

Paths use `lib/core`, `lib/features`, `lib/app`. `core/domain/result.dart`: sealed `Result<T>` with `Success<T>(value)`, `Failure<T>(AppFailure error)`; `AppFailure` fields code/message and getter isNetwork. Pure Dart.
`core/network/api_client.dart`: ApiClient(Dio dio), methods get/post/put returning decoded `Map<String,dynamic>`, upload(path,filePath,{fields}), bytes(path), and public Dio get dio. Shared network/auth data layers implement token storage and retry.
`core/security/token_store.dart`: TokenStore interface `Future<String?> readRefreshToken()`, `Future<void> saveTokens({required String accessToken,required String refreshToken})`, `Future<void> clear()`, `String? get accessToken`; SecureTokenStore implementation. No persistence of PII in plaintext.
AuthSessionCubit is app-scoped; KycCubit is authenticated-flow scoped. Root DI/router may compose both without feature flow-to-flow imports. Auth repository exposes use cases consumed by auth cubits. KYC repository/use cases consume ApiClient.

## Access and reviewer APIs

Public registration accepts only email/password and always creates `user`. One operator-only bootstrap creates the initial `super_admin`; management APIs permit only `user`/`reviewer` assignments and protect the owner. See [admin guide](../admin-access.md).

GET `/access/role-request` -> `{request:null|{id,userId,email,status,reason,decisionReason,createdAt,decidedAt}}`; POST same `{reason}` -> `{request}` (201), one pending request per user. GET `/admin/users?limit=50&offset=0` -> `{users:[{id,email,emailVerified,role,createdAt}],total}`; POST `{email,password,role}` -> `{user,nextStep:"VERIFY_EMAIL"}` (201). PUT `/admin/users/:userId/role` `{role,reason?}` -> `{user}`. GET `/admin/role-requests?status=pending&limit=50&offset=0` -> `{requests,total}`; POST `/admin/role-requests/:id/decision` `{decision:"approved"|"rejected",reason?}` -> `{request,user}`. Only super_admin can manage accounts/requests.

GET `/reviews?limit=50&offset=0` -> `{profiles:[{userId,email,status,submittedAt}],total}`; GET `/reviews/:userId` -> `{user:{id,email},profile}`; GET `/reviews/:userId/media/:kind` -> authenticated JPEG bytes, no-store; POST `/reviews/:userId/decision` `{decision:"verified"|"rejected",reason?,requiredSteps?}` -> `{profile}`. Reviewer/super_admin only; queue/detail/media require another user's pending profile. Rejection needs reason3–1000 and nonempty requiredSteps; verified has no correction steps. Roles are checked in the guard and inside privileged transactions. Lists default50/max100. Admin request statuses pending/approved/rejected. Role request reason10–1000; optional management reasons1–1000.

Access feature Cubits are route-scoped factories. AuthSessionCubit accepts a server-derived user update as an app-scoped contract; access does not read or coordinate KYC flow state. Reviewer photos remain in route-local memory and are cleared on authorization failure.
