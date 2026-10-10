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
