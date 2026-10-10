# Verification evidence

Verified locally on 10 October 2026 (Asia/Ho_Chi_Minh). The current backend is NestJS **12.1.2** with the Express adapter. The Flutter source did not change during the backend migration; its analysis, unit tests, formatting and platform builds below were completed earlier on the same mobile source. The real-API integration and delivered recording were rerun against the compiled NestJS backend.

| Check | Actual result |
|---|---|
| Nest backend `npm run check` and `npm run build` | Passed |
| Nest backend `npm test` | 14/14 passed on both Node 22.23.2 and Node 24.19.0, using real isolated PostgreSQL 18.1 and migrations 001–003 |
| Backend `npm audit`, including development dependencies | 0 vulnerabilities reported |
| Flutter `flutter analyze --no-pub` | No issues found; mobile source unchanged during migration |
| Flutter `flutter test --no-pub` | 41 tests passed; mobile source unchanged during migration |
| Flutter bundled Dart format check | 66 files checked, no changes required |
| `flutter build ios --simulator --debug` | Built Runner.app successfully on the unchanged mobile source |
| `flutter build apk --debug` | Built app-debug.apk successfully on the unchanged mobile source |
| Real-API iOS integration against compiled NestJS | Passed: registration/OTP, saved resume, interrupted upload/retry, private review, submission, rejection, resubmission, verified result and logout |
| SMTP/database readiness | Mailpit received the real registration OTP; `/health` returned `{status:"ok"}` |
| Delivered demo | Approximately 46 seconds, recorded against compiled NestJS, real PostgreSQL and Mailpit with synthetic document/selfie images |

The backend suite includes ten preserved behavior cases and four Nest-specific cases. The additional cases cover injectable module resolution, the error contract for invalid JSON/validation/unknown routes, authentication and upload guards before multipart parsing plus resource limits, and safe errors for private-media filesystem failures. Existing cases cover OTP expiry/attempt limits, session rotation/replay/concurrency, logout/reset revocation, durable encrypted mail, private image storage, authorization and KYC resubmission. Auth rate limits use controller metadata, including case-insensitive route coverage. A read-only migration audit also confirmed that all 33 Auth SQL statements were preserved.

## Integration scope

The iOS integration substitutes only camera capture with generated JPEGs because iOS Simulator cannot take a real photograph. A deliberate connection failure occurs before the first document upload to exercise retained capture and retry. Subsequent upload, image decoding/encryption, saved progress and private review use the compiled NestJS API and real PostgreSQL. Reviewer decisions are saved by a privileged local coordinator using the same review function as the CLI; no public mock verification endpoint is involved.

After saving details, the test recreates the whole Flutter app/container and restores from platform secure storage plus server progress. This verifies app/session restoration; an operating-system force-kill was not exercised. Android lost-camera-data recovery is covered by platform-boundary data tests.

An earlier Android emulator smoke used the real system Camera and production `image_picker` path: front selfie and back document capture, real upload, private Review, and cleanup of temporary captures. It predates the NestJS migration and the final capture-ID/session-race fixes, so it provides native platform evidence rather than a current-backend integration result. The final mobile source passed the focused recovery/session tests and both platform builds. Android Camera remembered its previous front lens despite the rear preference, so Back camera was selected manually for the document retake.

The local database runner was also smoke-tested: actual PostgreSQL 18.1 started on an isolated port with UTF8 and all migrations, then stopped. The supplied GitHub Actions workflow has not been run on GitHub in this local session. Node 22.12 is the minimum runtime; root `.nvmrc` selects Node 22.

## Remaining manual checks

Physical iOS/Android camera quality, denied permission → Settings → retry, OS force-kill while a native camera is open, real-device LAN/firewall behavior and store signing require appropriate hardware/accounts. Production infrastructure, retention, KMS rotation and identity-provider verification remain documented future work. Docker Compose is supplied; Docker was unavailable on this host, so the running demo and tests used real embedded PostgreSQL plus local Mailpit.

## Form and OTP improvements

Verified on 10 October 2026 after the migration evidence above. Auth password and confirmation fields now have independent show/hide controls. Date of birth uses a wheel picker with confirmation/cancel, friendly display, ISO persistence and the existing 18–120 age range. Verification renders six individual cells with native keyboard editing, autofill, full-code paste and correction. A valid login for an unverified account creates and attempts OTP delivery automatically, retaining the 30-second cooldown and encrypted mail retry.

| Check | Actual result |
|---|---|
| Backend `npm run check` | Passed |
| Backend `npm test` | 16/16 real HTTP/PostgreSQL tests passed |
| Flutter `flutter analyze --no-pub` | No issues found |
| Flutter `flutter test --no-pub --reporter expanded` | 57/57 passed, including architecture boundaries |
| Flutter bundled Dart format check | 72 files checked, no changes required |

Focused behavior tests were observed failing before their fixes. New cases cover password masking/toggles, confirmation validation, disabled loading controls, date selection/prefill/cancel/validation and age bounds, OTP leading zeroes, filtering, backspace, rapid cell selection, replacement paste, keyboard submission, validation and narrow screens with large text. The backend regressions cover OTP delivery on unverified login, wrong-password/disabled-account restrictions, cooldown, successful verification/login and SMTP outage recovery. The real-API integration source was updated for the new input controls; platform builds, the recorded demo and device integration were not rerun for this update.

## Submitted profile preview

Verified on 10 October 2026. Verification status now opens a scrollable, read-only preview for pending, verified and rejected submissions. It shows personal details, document type, private document/selfie photos and submission time, with loading/error/retry and a close control. The preview borrows the existing authenticated-flow Cubit and uses its private-media use case. Review and submission reuse the same summary while retaining their editing controls.

| Check | Actual result |
|---|---|
| `flutter test --no-pub test/features/kyc/verification_page_test.dart` | 11/11 passed; original missing-preview behavior observed failing before implementation |
| `flutter test --no-pub test/app test/architecture test/features/auth test/features/kyc test/widget_test.dart --reporter expanded` | 68/68 passed |
| Bundled Dart `analyze lib/features/kyc test/features/kyc/verification_page_test.dart` | No issues found |
| Bundled Dart format check on the six affected Dart files | No changes required |

The preview tests cover all submitted statuses, absence for incomplete/unloaded profiles, unchanged submitted data, authenticated in-memory images, loading and media retry, closing during image IO, refresh/resubmit after closing, and scrolling at 320px width with text scale 2. The whole-project analyzer was also attempted, but concurrent work in the new access feature had unresolved test imports/API definitions; those unrelated files were not modified by this change. Device builds and the real-API recording were not rerun for this presentation-only update.
