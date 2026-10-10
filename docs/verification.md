# Verification evidence

Performed locally on 10 October 2026 (Asia/Ho_Chi_Minh). Source repository started empty; commands below were executed during implementation. Automated platform substitutions are stated explicitly.

| Check | Actual result |
|---|---|
| Backend `npm run check` and `npm run build` | Passed |
| Backend `npm test` | 10 tests passed against real isolated PostgreSQL 18.1, migrations 001–003 |
| Backend `npm audit`, including development dependencies | 0 vulnerabilities reported |
| Flutter `flutter analyze --no-pub` | No issues found |
| Flutter `flutter test --no-pub` | 41 tests passed |
| Flutter bundled Dart format check | 66 files checked, no changes required |
| `flutter build ios --simulator --debug` | Built Runner.app successfully on iOS Simulator |
| `flutter build apk --debug` | Built app-debug.apk successfully |
| Real SMTP integration | Actual HTTP register returned 201 and Mailpit caught its OTP email |
| Live API/database | `/health` returned `{status:"ok"}` |
| Real-API iOS integration | Passed twice: registration/OTP, saved resume, interrupted upload/retry, private review, submission, rejection, resubmission, verified result and logout |
| Android native camera smoke | External system camera captured front selfie and back document, real upload succeeded, authenticated Review displayed both images; temporary capture cache was empty afterward |
| Local DB runner smoke | Actual PostgreSQL 18.1 started on isolated port 55440 with UTF8 and all migrations; stopped after smoke |

Focused tests were observed failing before implementation for route guards, auth restore/rotation, session races and byte-media refresh, generic SMTP response latency, KYC transitions, camera intent recovery and accepted-capture cleanup. Full checks were repeated after material fixes. The SMTP latency regression proves forgot/resend handlers respond while the mail transport is blocked without invoking it.

The real-API integration substitutes only camera capture with generated JPEGs. A deliberate connection failure occurs before the first document upload to exercise the real app’s retry path; subsequent upload, image decoding/encryption, state persistence and review all use the real API/PostgreSQL. Reviewer decisions are saved by a privileged local coordinator using the same review function as the CLI. No public mock verification endpoint is involved.

The integration recreates the whole Flutter app/container after saving details and restores from platform secure storage plus server progress. This is not a claim that an operating-system force-kill was exercised. Android lost-camera-data recovery is covered by platform-boundary data tests.

The Android smoke used an emulator's real system Camera and the production `image_picker` path. Its installed APK preceded the final capture-ID recovery/session-race changes; it validates native capture/upload/platform configuration. The final source passed the focused recovery/session tests and both platform builds. Android's external Camera remembered its previous front lens despite the rear preference, so Back camera was selected manually for the document retake. Physical camera quality remains a separate check.

The delivered `demo/full-flow.mp4` is about 46 seconds with synthetic document/selfie images. Frames were inspected for private review, rejection, verified result and logout. The GitHub Actions workflow is committed; it has not been run on GitHub in this local session.

## Remaining manual checks

Physical iOS/Android camera quality, denied permission → Settings → retry, OS force-kill while a native camera is open, real-device LAN/firewall behavior and store signing require appropriate hardware/accounts. Production infrastructure, retention, KMS rotation and identity-provider verification are documented future work. Docker Compose configuration is supplied; Docker was unavailable on this host, so the running demo and tests used real embedded PostgreSQL plus local Mailpit instead.
