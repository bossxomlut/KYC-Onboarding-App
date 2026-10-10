# Verification evidence

Verified locally on 10 October 2026 (Asia/Ho_Chi_Minh). The current backend is NestJS **12.1.2** with the Express adapter. The Flutter source did not change during the backend migration; its analysis, unit tests, formatting and platform builds below were completed earlier on the same mobile source. The real-API integration and delivered recording were rerun against the compiled NestJS backend.

| Check                                                   | Actual result                                                                                                                                     |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nest backend `npm run check` and `npm run build`        | Passed                                                                                                                                            |
| Nest backend `npm test`                                 | 14/14 passed on both Node 22.23.2 and Node 24.19.0, using real isolated PostgreSQL 18.1 and migrations 001–003                                    |
| Backend `npm audit`, including development dependencies | 0 vulnerabilities reported                                                                                                                        |
| Flutter `flutter analyze --no-pub`                      | No issues found; mobile source unchanged during migration                                                                                         |
| Flutter `flutter test --no-pub`                         | 41 tests passed; mobile source unchanged during migration                                                                                         |
| Flutter bundled Dart format check                       | 66 files checked, no changes required                                                                                                             |
| `flutter build ios --simulator --debug`                 | Built Runner.app successfully on the unchanged mobile source                                                                                      |
| `flutter build apk --debug`                             | Built app-debug.apk successfully on the unchanged mobile source                                                                                   |
| Real-API iOS integration against compiled NestJS        | Passed: registration/OTP, saved resume, interrupted upload/retry, private review, submission, rejection, resubmission, verified result and logout |
| SMTP/database readiness                                 | Mailpit received the real registration OTP; `/health` returned `{status:"ok"}`                                                                    |
| Delivered demo                                          | Approximately 46 seconds, recorded against compiled NestJS, real PostgreSQL and Mailpit with synthetic document/selfie images                     |

The backend suite includes ten preserved behavior cases and four Nest-specific cases. The additional cases cover injectable module resolution, the error contract for invalid JSON/validation/unknown routes, authentication and upload guards before multipart parsing plus resource limits, and safe errors for private-media filesystem failures. Existing cases cover OTP expiry/attempt limits, session rotation/replay/concurrency, logout/reset revocation, durable encrypted mail, private image storage, authorization and KYC resubmission. Auth rate limits use controller metadata, including case-insensitive route coverage. A read-only migration audit also confirmed that all 33 Auth SQL statements were preserved.

## Integration scope

The iOS integration substitutes only camera capture with generated JPEGs because iOS Simulator cannot take a real photograph. A deliberate connection failure occurs before the first document upload to exercise retained capture and retry. Subsequent upload, image decoding/encryption, saved progress and private review use the compiled NestJS API and real PostgreSQL. The earlier recording saved reviewer decisions through a privileged local coordinator using the shared review operation. The coordinator now supplies an authorized synthetic reviewer actor; the current app also has authenticated reviewer screens. No public mock verification endpoint is involved.

After saving details, the test recreates the whole Flutter app/container and restores from platform secure storage plus server progress. This verifies app/session restoration; an operating-system force-kill was not exercised. Android lost-camera-data recovery is covered by platform-boundary data tests.

An earlier Android emulator smoke used the real system Camera and production `image_picker` path: front selfie and back document capture, real upload, private Review, and cleanup of temporary captures. It predates the NestJS migration and the final capture-ID/session-race fixes, so it provides native platform evidence rather than a current-backend integration result. The final mobile source passed the focused recovery/session tests and both platform builds. Android Camera remembered its previous front lens despite the rear preference, so Back camera was selected manually for the document retake.

The local database runner was also smoke-tested: actual PostgreSQL 18.1 started on an isolated port with UTF8 and all migrations, then stopped. The supplied GitHub Actions workflow has not been run on GitHub in this local session. Node 22.12 is the minimum runtime; root `.nvmrc` selects Node 22.

## Remaining manual checks

Physical iOS/Android camera quality, denied permission → Settings → retry, OS force-kill while a native camera is open, real-device LAN/firewall behavior and store signing require appropriate hardware/accounts. Production infrastructure, retention, KMS rotation and identity-provider verification remain documented future work. Docker Compose is supplied; Docker was unavailable on this host, so the running demo and tests used real embedded PostgreSQL plus local Mailpit.

## Form and OTP improvements

Verified on 10 October 2026 after the migration evidence above. Auth password and confirmation fields now have independent show/hide controls. Date of birth uses a wheel picker with confirmation/cancel, friendly display, ISO persistence and the existing 18–120 age range. Verification renders six individual cells with native keyboard editing, autofill, full-code paste and correction. A valid login for an unverified account creates and attempts OTP delivery automatically, retaining the 30-second cooldown and encrypted mail retry.

| Check                                               | Actual result                                   |
| --------------------------------------------------- | ----------------------------------------------- |
| Backend `npm run check`                             | Passed                                          |
| Backend `npm test`                                  | 16/16 real HTTP/PostgreSQL tests passed         |
| Flutter `flutter analyze --no-pub`                  | No issues found                                 |
| Flutter `flutter test --no-pub --reporter expanded` | 57/57 passed, including architecture boundaries |
| Flutter bundled Dart format check                   | 72 files checked, no changes required           |

Focused behavior tests were observed failing before their fixes. New cases cover password masking/toggles, confirmation validation, disabled loading controls, date selection/prefill/cancel/validation and age bounds, OTP leading zeroes, filtering, backspace, rapid cell selection, replacement paste, keyboard submission, validation and narrow screens with large text. The backend regressions cover OTP delivery on unverified login, wrong-password/disabled-account restrictions, cooldown, successful verification/login and SMTP outage recovery. The real-API integration source was updated for the new input controls; platform builds, the recorded demo and device integration were not rerun for this update.

## Submitted profile preview

Verified on 10 October 2026. Verification status now opens a scrollable, read-only preview for pending, verified and rejected submissions. It shows personal details, document type, private document/selfie photos and submission time, with loading/error/retry and a close control. The preview borrows the existing authenticated-flow Cubit and uses its private-media use case. Review and submission reuse the same summary while retaining their editing controls.

| Check                                                                                                                             | Actual result                                                                          |
| --------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `flutter test --no-pub test/features/kyc/verification_page_test.dart`                                                             | 11/11 passed; original missing-preview behavior observed failing before implementation |
| `flutter test --no-pub test/app test/architecture test/features/auth test/features/kyc test/widget_test.dart --reporter expanded` | 68/68 passed                                                                           |
| Bundled Dart `analyze lib/features/kyc test/features/kyc/verification_page_test.dart`                                             | No issues found                                                                        |
| Bundled Dart format check on the six affected Dart files                                                                          | No changes required                                                                    |

The preview tests cover all submitted statuses, absence for incomplete/unloaded profiles, unchanged submitted data, authenticated in-memory images, loading and media retry, closing during image IO, refresh/resubmit after closing, and scrolling at 320px width with text scale 2. The whole-project analyzer was also attempted, but concurrent work in the new access feature had unresolved test imports/API definitions; those unrelated files were not modified by this change. Device builds and the real-API recording were not rerun for this presentation-only update.

## Account permissions and reviewer workflow

Verified on 10 October 2026. The app now supports one bootstrap super admin, managed user/reviewer creation, direct grant/revoke, user permission requests, and authenticated review queue/detail/media/decisions. Existing accounts migrate to user; public signup cannot choose a role. Every privileged request checks the live role, and privileged transactions lock/check the actor again. New decisions and role changes record their actor. Direct CLI reviews no longer write to PostgreSQL.

| Check                                     | Actual result                                                                                                                                                                     |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Backend `npm test`                        | 33/33 passed with disposable PostgreSQL and migrations 001–004                                                                                                                    |
| Backend `npm run check` / `npm run build` | Passed                                                                                                                                                                            |
| Flutter `flutter analyze --no-pub`        | No issues found                                                                                                                                                                   |
| Flutter `flutter test --no-pub`           | 90/90 passed, including architecture boundaries                                                                                                                                   |
| Bundled Dart format check                 | 95 files, no changes required                                                                                                                                                     |
| Flutter iOS Simulator debug build         | Passed                                                                                                                                                                            |
| Flutter Android debug APK build           | Passed with emulator API URL                                                                                                                                                      |
| Compiled local API bootstrap smoke        | Health200; admin login200; `/auth/me` reports verified super_admin; privileged invalid body reaches validation400; unauthenticated reviews401; temporary smoke session logged out |
| Local bootstrap repeat                    | Existing owner and credentials preserved; generated credential file has mode600 and is Git-ignored                                                                                |

Focused permission tests were observed failing before implementation. Coverage includes role injection, ordinary-user restrictions, protected owner, OTP for managed accounts, audit identity/reason, pending-request uniqueness, approval/rejection, direct grants, request pagination/isolation, role revocation with existing JWTs, self-review denial, authenticated private JPEGs, concurrent decisions, bootstrap concurrency/idempotency and email outage persistence. The 22 new Flutter tests cover roles/routes, mappings, requests/admin creation/decisions, rejection validation, missing-media gating, clearing private data on authorization/stale-review failures, image-cache eviction, role refresh during logout and retaining reload errors after successful mutations.

Automated permission tests use isolated synthetic data. The only live account operation for this change was the explicitly requested default super admin bootstrap and a login/validation smoke for that new synthetic admin; other users and their KYC records were not inspected. The earlier real-API video has not been rerecorded for these new management screens. See [admin guide](admin-access.md) for operation and account credentials.

## Admin Home and status highlighting

Verified on 10 October 2026. Local bootstrap now defaults to `admin@kyc.com`; the existing local owner email was updated as requested, preserving its ID, role and password. Its old sessions and outstanding email/reset tokens were invalidated, and the ignored local credentials file was synchronized with mode 600. No other users or their profiles/media were inspected.

Super admin Home now contains only account identity, Manage accounts, Review profiles and logout. Admins bypass the applicant KYC provider/profile fetch, and old KYC deep links redirect home. User/reviewer applicant flows retain their behavior. Home, verification result and submitted profile summaries share a presentation-only status badge: gray, blue, amber, green and red for not_started, in_progress, pending_review, verified and rejected. Each badge includes an icon, readable label, tinted background and border.

| Check                                                                                        | Actual result                                                                                             |
| -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Backend `npm run check` / `npm run build`                                                    | Passed                                                                                                    |
| Live local admin login, `/auth/me`, logout                                                   | All 200; new email and super_admin role confirmed; smoke session cleaned up                               |
| Repeat local bootstrap                                                                       | Existing owner and password preserved                                                                     |
| Flutter `flutter analyze --no-pub`                                                           | No issues found                                                                                           |
| All mobile tests (`test/app`, `test/architecture`, `test/features`, `test/widget_test.dart`) | 114/114 passed                                                                                            |
| Bundled Dart format check                                                                    | 100 files, no changes required                                                                            |
| Flutter iOS Simulator debug build                                                            | Passed with loopback API URL                                                                              |
| Flutter Android debug APK build                                                              | Passed with emulator API URL                                                                              |
| Visual inspection                                                                            | Six synthetic renders at 390×844: admin, five badges, user Home and three submitted statuses; no overflow |

Focused route/app tests reproduced the old admin applicant-flow behavior before implementation. New coverage verifies KYC deep-link redirection, no admin KYC requests, logout success/failure/loading, both admin actions, 320px screens with text scale 2, distinct icons/labels and text contrast of at least 4.5:1. Existing full KYC upload/retry/submission and submitted-profile preview tests also passed. Visual fixtures and tests use synthetic data only; the real-API video was not rerecorded for this UI update.

## Capture continuation

Verified on 10 October 2026. Document and selfie uploads now keep the user on the capture page with the uploaded photo visible. Continue navigates to the server's next step only after a successful upload and an explicit tap. Upload retries follow the same rule; unfinished replacement photos and busy operations disable Continue, while canceled retakes preserve existing uploaded progress.

| Check | Actual result |
| --- | --- |
| `flutter test --no-pub test/features/kyc/capture_page_test.dart test/features/kyc/kyc_flow_widget_test.dart test/features/kyc/kyc_cubit_test.dart --reporter expanded` | 17/17 passed; auto-navigation and missing post-upload preview observed failing before the fix |
| `flutter test --no-pub --reporter expanded` | 123/123 passed, including architecture boundaries |
| `flutter analyze --no-pub` | No issues found |
| Bundled Dart format check on the six affected Dart files; `git diff --check` | Passed |

Nine new widget cases cover both media kinds, explicit continuation after success, disabled controls before/during upload, photo preview, capture cancellation, failed replacement/retry, canceled retakes and returning from an edited document to the server-selected review step. The full KYC widget flow still submits successfully after document retry and selfie continuation. The real-API integration source now taps Continue for document, selfie and rejected-selfie resubmission. Device integration, native camera checks, platform builds and the demo recording were not rerun for this update.

## Device Back navigation

Verified on 10 October 2026. System Back from authenticated feature pages now returns Home. Dialogs and bottom sheets close before leaving their page, and Home still delegates Back to the operating system. KYC loading/error screens retain the shell Navigator, and returning Home preserves the flow Cubit. Saves, submissions, resubmissions and reviewer decisions completing immediately after Back no longer navigate away from Home.

| Check | Actual result |
| --- | --- |
| `flutter test --no-pub test/app/system_back_test.dart test/app/predictive_back_test.dart --reporter expanded` | 20/20 passed; original system-Back failure and post-Back submission navigation observed failing before their fixes |
| `flutter test test/app/back_pending_operations_test.dart` | 3/3 passed for saving details, resubmission and reviewer approval finishing immediately after Back |
| `flutter test --no-pub --reporter expanded` | 146/146 passed, including architecture boundaries and existing KYC flows |
| `flutter analyze --no-pub` | No issues found |
| Bundled Dart format check on ten affected Dart files; `git diff --check` | Passed |
| `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1` | Passed; `mobile/build/app/outputs/flutter-apk/app-debug.apk` |

The new tests exercise the production app/router with synthetic HTTP/platform substitutes. They cover all nine feature routes, modal dismissal, Home system exit, profile loading/failure, KYC provider lifetime and completion races before the previous page is disposed. Android navigation-channel tests verify that Flutter advertises Back handling across KYC steps and after modal dismissal, then releases it at Home. Physical-device/emulator Back button presses, real-API device integration, iOS builds and the recording were not rerun for this update.

## Submission history and reviewer attribution

Verified on 10 October 2026. Every submit now creates a separate encrypted submission snapshot, including references to its original document and selfie. Rejection and resubmission preserve the previous version, and new decisions capture the authenticated reviewer's ID, email, role and review time. Home and verification status expose applicant history; reviewer detail exposes prior submissions for comparison. Historical detail is read-only and loads private images through authenticated endpoints.

| Check | Actual result |
| --- | --- |
| Backend focused history and migration tests | 9/9 passed against disposable real PostgreSQL and Nest HTTP; missing history routes and missing migration observed failing before implementation |
| Backend `npm run check`, `npm run build`, full `npm test` on Node24.19.0 | Passed; 42/42 tests |
| History feature data/Cubit/widget tests | 16/16 passed; focused cases observed failing before their implementations, including legacy final records without an audit |
| `flutter test --no-pub --reporter expanded` | 169/169 passed, including architecture boundaries, existing KYC flows and history navigation |
| `flutter analyze --no-pub` | No issues found |
| Bundled Dart format check on 22 affected files, backend Prettier checks, `git diff --check` | Passed |
| `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1` | Passed |
| Local `npm run migrate` and compiled API restart | Passed; health200 and unauthenticated new history route401 |
| Synthetic visual inspection | List and read-only detail at390×844 with real fonts; large text scale2 widget case passed |

Backend coverage verifies submission retry/concurrency, version order/pagination, owner isolation, live role revocation, original personal details and exact photo bytes across multiple rounds, retained reviewer identity after email/role changes, and preserving an accepted document when retaken after a partial rejection. An unsubmitted retake still deletes its obsolete file. The upgrade test applies migrations001–004 to a legacy database before005 and preserves only the actually available current submission and matching review audit.

Migration005 was applied to the configured local development database without displaying existing applicant records. Previously overwritten details and deleted photos cannot be recovered. Legacy audits retain known reviewer IDs but cannot supply historical email/role values that were never stored; missing audit timestamps remain unavailable. A local authenticated smoke using the existing ignored synthetic-admin credential file returned401 INVALID_CREDENTIALS; credentials/accounts were not changed and no smoke session was created. Authenticated history checks passed in the isolated backend suite. Real-API device integration, native camera checks, iOS builds and the recording were not rerun. The integration-test source now verifies reading the rejected round after the replacement round becomes verified.

## Background and foreground recovery

Verified on 10 October 2026. One app-owned observer recognizes actual background cycles and revalidates the live session before refreshing the current screen. Focus-only interruptions do not reload. Forms, capture previews and open history sheets retain their state; access/reviewer actions wait for fresh permissions/data. KYC reads coalesce and queue behind active operations without repeating writes. Old permission/profile responses cannot override newer foreground data, including two background cycles while a response is delayed. History refresh keeps the loaded pages and removes duplicate submission IDs when offset pages shift.

Reviewer detail, private photos and decisions now share an immutable `submissionId`. The backend rejects an old ID against a newer pending submission before writing a decision or audit. OTP resend uses a 30-second wall-clock deadline and does not send automatically on resume. A new reset link clears the old form/token; successful reset completion still invalidates its original app session after the form changes or closes. Atomic token clearing preserves a newer login.

| Check | Actual result |
| --- | --- |
| Full Flutter `flutter test --no-pub --reporter expanded` | 227/227 passed, including architecture boundaries and existing Back/KYC/history flows |
| Focused app resume/reset widget tests and session retry tests | 22/22 passed on final UI source |
| Flutter `flutter analyze --no-pub` | No issues found |
| Bundled Dart format check on `lib test integration_test` | 128 files, no changes required |
| Backend `npm run check`, `npm run build`, full `npm test` | Passed; 44/44 tests with isolated PostgreSQL/Nest HTTP coverage |
| Changed backend Prettier checks and `git diff --check` | Passed |
| `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1` | Passed; `mobile/build/app/outputs/flutter-apk/app-debug.apk` |

Focused tests reproduced the incorrect focus-only reload, missing foreground reads, stale permissions/profile responses, skipped trailing refresh, stale/missing photo cache, wrong read Retry, drifting OTP cooldown, old reset token/completion, clearing a newer login, and duplicate history cards before their fixes. Backend regressions submit a new version after rejection and prove that old-version photos/decisions are rejected without a new audit; the latest version can still be reviewed.

Backend/mobile must be updated together because reviewer photo and decision requests now require `submissionId`; older clients receive validation400. No new database migration is needed. This update does not add durable unsaved form drafts: normal background transitions preserve memory, while process termination restores saved server progress and existing private capture recovery. Real-device camera/permission → Settings transitions, OS force-kill, real-API device integration, iOS builds and the recording were not rerun for this change. The running development API and installed app were not replaced by these automated checks.
