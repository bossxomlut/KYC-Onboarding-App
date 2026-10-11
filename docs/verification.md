# Verification

Run these checks after following [local setup](local-setup.md). Use Node 22.12+ and Flutter 3.44.6 with its bundled Dart SDK. Commands below describe how to reproduce checks; the dated results record earlier development runs and do not claim a new full run during repository cleanup.

## Repository cleanup checks

On 11 Oct 2026, after removing old recordings, screenshot renderers and generated artifacts: `npm run check`, `flutter analyze --no-pub`, `flutter test --no-pub test/architecture --reporter expanded` (1/1), local Markdown file-link checks and `git diff --check` passed. Production source and normal unit/integration tests were unchanged. Full behavior suites, native builds and destructive data-reset commands were not rerun for this cleanup.

## Main-flow recording

On 11 Oct 2026, `python3 demo/record-full-flow.py` built and ran the recording-only integration target on iPhone 17 Pro (iOS 26.2 Simulator). The real API integration passed **1/1**, including registration/OTP, explicit login, saved session/progress, private fixture uploads, edit/retake, authenticated reviewer rejection and approval, selfie-only resubmission, Verified, immutable history and logout. Focused Flutter analysis, Dart formatting, the architecture test (**1/1**), Python syntax and recorder TypeScript/JSON formatting passed. Production app/backend source was unchanged.

The retained [MP4](../demo/full-flow.mp4), [chapter timestamps](../demo/full-flow.chapters.json) and [demo guide](../demo/README.md) use fictional data from `demo/scenario.json` and marked illustrations. The recording ran against a separate disposable PostgreSQL database/API/Mailpit and did not read or modify the development database. Camera capture was substituted on the simulator; session restoration recreated the app/container rather than force-killing it. This recording does not establish physical-camera, liveness or OCR/face accuracy.

The [Vietnamese narrated variant](../demo/full-flow-voiced.mp4) was generated locally with the macOS Linh voice from 18 timed passages. All passages fit their intervals at the configured rate without speeding up; the final speech ends at 219.049s, before the 220.267s video ends. FFprobe confirms Vietnamese AAC audio, 720×1566 H.264 at 30fps and all 42 chapters. The encoded video stream hash matches the silent original; full audio/video decoding and per-passage non-silence checks passed. See the editable [narration plan](../demo/voiceover.vi.json) and [timing report](../demo/voiceover.vi.report.json).

## Automated checks

From the repository root, after `npm ci` in `backend` and `flutter pub get` in `mobile`:

```sh
./scripts/check.sh
```

This runs setup-script and Python engine tests, backend TypeScript checks and HTTP/database tests, Dart formatting, Flutter analysis and Flutter tests. Backend tests launch disposable real PostgreSQL instances and apply migrations; they do not use the development database. Flutter unit/widget tests substitute HTTP and platform boundaries with synthetic data.

Individual commands, from the indicated directories:

```sh
# Repository root
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test_local_verification_setup.py
PYTHONDONTWRITEBYTECODE=1 python3 backend/local-verification/test_engine.py

# backend/
npm run check
npm test
npm run build

# mobile/
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

Optional native build checks, from `mobile/`:

```sh
flutter build ios --simulator --debug --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

For a physical phone, use the Mac's current LAN address instead of the emulator address. An installed app must be rebuilt when its compiled API address or native configuration changes. Rebuilding the API also requires restarting its running process.

## Coverage

- Authentication: OTP expiry, attempt limits, cooldown, email outages, password reset, single-use codes, session rotation/replay/concurrency, revocation and preserving a newer login after a delayed operation.
- Authorization and review: live role checks, protected bootstrap admin, permission requests, private-media access, concurrent decisions, stale submission IDs, stored reviewer attribution, queue filtering/search and pagination.
- KYC persistence: input/upload validation, private encrypted storage, upload retry, explicit continuation, rejection/resubmission, immutable history, original photo retention and legacy migration behavior.
- Flutter: domain/data/presentation boundaries, provider ownership, route guards, Back/stack navigation, foreground refresh, stale response/completion handling, retained forms/photos, narrow layouts and large text.
- Camera and identity checks: permission/error handling, resource cleanup, capture recovery, orientation/crop/mirror mapping, strict evidence parsing, optional provider failures, submission sequencing and reviewer-only evidence visibility.

## Recorded results

Dates use Asia/Ho_Chi_Minh. Counts describe the checkout at each recorded run; focused suites overlap and must not be added together. Later feature changes can increase the current count. These results are historical evidence, not a guarantee that every command above passed after subsequent edits.

| Date | Recorded check | Result |
| --- | --- | --- |
| 10 Oct 2026 | Nest migration suite on Node 22.23.2 and 24.19.0 | 14/14 backend tests; TypeScript/build passed |
| 10 Oct 2026 | iOS Simulator integration after the final visual revision | Passed registration/OTP, saved session/progress, failed upload/retry, private review, rejection/resubmission, verified result, historical submission and logout |
| 11 Oct 2026 | Android in-app camera runtime checks | Both lenses, private persistence/recovery and portrait/landscape crop alignment exercised on an emulator |
| 11 Oct 2026 | Full backend suite after password-reset OTP work, Node 24.19.0 | 112/112 passed; TypeScript/build passed |
| 11 Oct 2026 | Full Flutter suite after compact reviewer evidence work | 494/494 passed; analyzer reported no issues |
| 11 Oct 2026 | Local Python engine and TypeScript adapter after noisy-label parser fix | 45/45 Python and 10/10 adapter cases passed |
| 11 Oct 2026 | Concurrent-review attribution regressions | 19/19 combined review/history cases, followed by an 11/11 review rerun; focused Flutter access suite 74/74 passed |
| 11 Oct 2026 | Submission-history Back navigation | 59/59 focused Flutter tests passed; analyzer reported no issues |
| 11 Oct 2026 | Live password-reset API/Mailpit smoke | Registration/verification/reset succeeded; code replay and revoked/old-password access rejected; new-password login succeeded |

The password-reset smoke removed its synthetic account, sessions, codes and Mailpit messages afterward. Earlier failing regressions drove the fixes; a concurrent whole-mobile run with one summary failure was superseded by the recorded 494/494 run. GitHub Actions and Docker Compose were supplied but were not executed on this development host during the recorded checks.

## Real API and camera checks

The [synthetic integration guide](../demo/README.md) describes running the real API flow with PostgreSQL, Mailpit and the privileged synthetic reviewer coordinator. It replaces only camera capture with test JPEGs because iOS Simulator has no physical camera. A deliberate failure happens before the first document upload; later HTTP, SQL, decoding/encryption and private-media requests use production implementations. Recreating the app/container tests secure-session and saved-progress restoration, rather than an operating-system force-kill.

To exercise real camera capture without an API account, from `mobile/`:

```sh
flutter test integration_test/in_app_camera_smoke_test.dart -d DEVICE_ID
```

Use an Android emulator/device or a physical iPhone. The default smoke test dispatches lifecycle notifications; it does not independently prove OS background/force-kill recovery. Native emulator checks also exercised leaving and reopening the camera. Synthetic emulator scenes and transformed sample portraits do not establish physical-camera quality or identity accuracy.

## Local OCR and face comparison

On 11 Oct 2026, the development Mac ran the actual Tesseract Vietnamese OCR and OpenCV YuNet/SFace engine with threshold `36.3`. Setup-script tests passed 4/4, and the installed runtime/models passed `python3 scripts/setup-local-verification.py --check`. See [provider setup and limitations](identity-verification.md) to reproduce the installation.

Authenticated synthetic API cases uploaded JPEGs, checked identity, submitted, then read reviewer detail and immutable history. They verified cache reuse, encrypted storage and equal decrypted evidence. Temporary accounts, sessions and media were removed afterward.

| Synthetic case | Selfie detection | Face comparison |
| --- | --- | --- |
| Document portrait and transformed copy as selfie | `detected` | `matched`, score 90.53 |
| Same document and another sample portrait | `detected` | `not_matched`, score 8.94 |
| Same document and blank selfie | `no_face` | `no_face` |
| Same document and two selfie portraits | `multiple_faces` | `multiple_faces` |
| Blank document and a valid portrait selfie | `detected` | `no_face` |

The first four cases extracted the synthetic Vietnamese name, ISO birth date and document number; the blank document returned `no_text`. A later real-Tesseract parser check recovered noisy bilingual labels while preserving number characters/leading zeroes. Invalid/ambiguous dates and unrelated phone/house/account labels remain unassigned. That parser fix did not repeat the full authenticated upload-to-review flow.

On the same date, Android emulator and Samsung SM A235F debug builds were installed and launched, with API health reachable; an iPhone 17 Pro simulator build also launched. The later compact reviewer update was built/installed on Samsung. These checks confirm startup/connectivity; they did not perform the complete physical-camera-to-review interaction. Generated builds, screenshots and previous recordings are disposable development artifacts. The current synthetic main-flow recording is retained separately in `demo/full-flow.mp4`.

## Remaining manual checks and limits

Physical iOS/Android camera quality, permission denial followed by Settings/retry, force-kill during capture, and complete physical-device capture/upload/review/password recovery still need hardware validation. Unsaved form edits survive ordinary background transitions in memory; process termination restores saved server progress and recoverable private captures, not durable unsaved forms.

No live AWS calls, real-user OCR/face accuracy calibration, liveness or document-authenticity checks were performed. Synthetic matching examples demonstrate integration only. Provider results assist manual review and do not decide KYC status. Store signing, production infrastructure, retention/deletion policy, KMS rotation and production monitoring remain follow-up work.
