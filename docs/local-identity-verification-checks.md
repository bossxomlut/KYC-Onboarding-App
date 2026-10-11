# Local OCR and face comparison: verification evidence

Verified on 11 October 2026 (Asia/Ho_Chi_Minh). The development API is now configured with `KYC_VERIFICATION_PROVIDER=local`, Vietnamese OCR and a SFace threshold of `36.3`. Tesseract, the isolated Python runtime and the checksum-verified YuNet/SFace/language files are installed on the development Mac. The API was restarted on Node24 and uses this configuration. This supersedes the earlier disabled-provider smoke recorded in [verification history](verification.md#ocr-and-selfiedocument-comparison).

The local engine performs real OCR and one-to-one face comparison on the app server, without AWS credentials or identity-service network calls. It supports manual KYC review; it does not make approval decisions.

## Automated checks

| Check | Actual result |
| --- | --- |
| Backend full suite on Node24; TypeScript check/build; affected-file Prettier check | 86/86 passed; check/build/format passed |
| Python engine unit tests | 25/25 passed, including TSV OCR parsing, Vietnamese labels/dates, malformed images, partial failures and face thresholds |
| Setup-script unit tests | 4/4 passed, including checksum rejection, atomic installation, cached downloads and virtualenv path preservation |
| Local setup rerun and `python3 scripts/setup-local-verification.py --check` | Passed; real OCR and face engines report ready |
| Focused Flutter verification tests | 45/45 passed; local provider parsing, disclosure, summary and existing verification behavior |
| Architecture boundary test | 1/1 passed |
| Final full `flutter test --no-pub` | 348/348 passed; this shared checkout also includes concurrent admin/auth work |
| Final `flutter analyze --no-pub` | No issues found |
| Production summary renderer using an actual local API result | 1/1 passed; inspected `output/identity-verification/local-completed-checks.png` at 390×844 logical pixels |

New Node cases cover the local process protocol, bounded input/output, invalid evidence, process-group timeout, provider selection and cache invalidation after a provider, threshold or OCR-language change. Existing storage, stale-media, submission and reviewer checks remain covered. The Python tests substitute native boundaries; the following smoke runs exercise the actual native engines.

## Live API and storage

Authenticated requests against the running local API created temporary synthetic applicants, uploaded document/selfie JPEGs, ran checks, submitted profiles and read both reviewer details and immutable history. All three cases returned HTTP200 with completed results:

| Fixture | OCR | Face result |
| --- | --- | --- |
| Sample portrait with a rotated/brightness-adjusted copy as selfie | `NGUYỄN MINH AN`, `1995-06-15`, `001234567890` | `matched`, similarity `90.53`, threshold `36.3` |
| Same document with a different sample portrait as selfie | Same extracted fields | `not_matched`, similarity `8.94` |
| Same document with a blank selfie | Same extracted fields | `no_face`, no similarity |

Each case also verified same-source result caching, encrypted database storage, correct decrypted evidence and identical results in submission history and reviewer detail. Temporary accounts, sessions and uploaded media were removed afterward. Existing applicant data and decisions were preserved. Images went through the real authenticated upload/check endpoints; they were not replaced with stubbed provider results.

The documents are clearly labeled synthetic test images, and portraits come from OpenCV sample fixtures. The positive face case uses a transformed copy of the same reference photograph. These checks demonstrate working integration, not accuracy calibration for real CCCD photographs or varied real users.

## Builds and installed devices

| Target | Actual result |
| --- | --- |
| Android debug APK for emulator, API `http://10.0.2.2:3000/api/v1` | Built, installed and launched on the Android emulator; backend health reachable |
| Android debug APK for LAN, API `http://192.168.2.18:3000/api/v1` | Built, installed and launched on Samsung SM A235F; backend health HTTP200 from the phone |
| iOS debug simulator app, API `http://127.0.0.1:3000/api/v1` | Built, installed and launched on iPhone17 Pro simulator; process alive |

The LAN APK is preserved at `output/android/app-local-lan-debug.apk`. Existing app data was retained. Local-provider strings and each target's API address were checked in the compiled artifacts; startup checks found no unhandled parser errors. The phone must stay on the same network as the Mac while its backend and PostgreSQL are running.

The feature's real API flow and production result panel were tested separately from native installation/startup. A complete camera-to-result interaction on the physical phone was not performed. Liveness, document authenticity checks, real-user accuracy evaluation and live AWS calls remain outside this verification. See [setup and behavior](identity-verification.md) to run the local feature or configure AWS later.

## Independent selfie face check

Verified later on 11 October 2026 (Asia/Ho_Chi_Minh). Results now include a separate `selfieFace` presence check followed by document/selfie comparison. A detected selfie face stays detected when the document has no face or recognition fails. Missing, multiple or failed selfie detection prevents comparison. Human-face detection does not establish liveness.

| Check | Actual result |
| --- | --- |
| Backend full suite, TypeScript check/build, affected-file Prettier | 102/102 passed; check/build/format passed |
| AWS adapter focused suite | 25/25 passed, including independent image preparation, missing document faces, detection/comparison failure and timeout, and late responses; no live AWS calls |
| Local adapter and authenticated KYC persistence focused suite | 24/24 passed; new cases were observed failing before implementation |
| Python engine unit suite and Ruff | 36/36 passed; format/check passed; new detection cases were observed failing first |
| Actual Python CLI using installed models | Six cases passed: same/different faces, blank/multiple-face selfies, blank document and invalid document |
| Flutter KYC and architecture focused suite | 58/58 passed, including strict parsing, stale evidence, legacy history, independent results and narrow/large-text layout |
| Flutter full suite and analyzer | 397/397 passed; no analyzer issues. This shared checkout included the committed in-app camera-guide work; later unrelated document-crop edits were preserved separately |
| Production summary renderer with the new live API result | 1/1 passed; inspected both `local-completed-checks.png` and scrolled `local-face-checks.png` at 390×844 logical pixels |
| Android LAN APK | Built, installed with existing data retained and launched on Samsung; API health HTTP200 and both face-check labels confirmed in the compiled artifact |

Five authenticated API cases using actual local inference all returned HTTP200 with completed evidence:

| Fixture | Selfie face check | Face comparison |
| --- | --- | --- |
| Document and transformed same portrait | `detected` | `matched`, similarity `90.53` |
| Document and different portrait | `detected` | `not_matched`, similarity `8.94` |
| Document and blank selfie | `no_face` | `no_face` |
| Document and two sample portraits in the selfie | `multiple_faces` | `multiple_faces` |
| Blank document and valid selfie portrait | `detected` | `no_face` |

Each API case also verified cache reuse, encrypted evidence, submission-history preservation and reviewer-detail equality, then removed its temporary accounts, sessions and media. The first four cases retained the same Vietnamese OCR fields shown above; the blank document correctly returned `no_text`. Synthetic fixtures demonstrate the independent integration without claiming real-user accuracy calibration.

Historical evidence without `selfieFace` is normalized to null and displays “Selfie face check was not recorded.” Editable profiles invalidate that legacy evidence and can run checks again; immutable history keeps the original comparison. No database migration is needed. New provider failures preserve other completed checks, and stale-photo guards also reject leftover selfie-detection evidence.

The physical-device checks cover installation, startup and backend connectivity; the complete camera-to-result interaction on Samsung was not performed. The updated LAN APK remains at `output/android/app-local-lan-debug.apk`.

## Reviewer-only compact results

Verified on 11 October 2026 (Asia/Ho_Chi_Minh). Applicant Review, status/profile previews and submission history now hide the identity-check panel and provider details. The applicant uses the ordinary Submit action; enabled, unfinished checks run before submission under one busy operation. Completed/disabled/missing check configurations skip an extra request. Optional provider failures allow manual submission; lost authority, stale inputs, background invalidation or a closed flow stop the subsequent write. No provider calls happen just from opening a page or history.

Reviewer detail and reviewer history retain real encrypted evidence in a compact **Identity checks** panel: OCR status/fields/confidence, Selfie, Face match, actual score/threshold and check time. Raw OCR is collapsed under **OCR text**. Missing extracted fields use `—`, absent historical selfie evidence uses **Not recorded**, and failures retain other available evidence. The panel has no provider branding or long explanatory paragraphs; the short **No liveness check** note remains.

| Check | Actual result |
| --- | --- |
| Submission, verification, Cubit, refresh and architecture focused tests | 81/81 passed; new sequence/failure/race cases were observed failing first |
| Applicant/reviewer summary, history and navigation focused tests | 20/20 passed; four applicant evidence leaks were observed before the visibility fix |
| Compact summary, both reviewer renderers and architecture | 28/28 passed; missing-component failure regression observed first, then fixed |
| Final full `flutter test --no-pub` | 494/494 passed; includes concurrent camera cropping and password-reset work in this shared checkout |
| Final `flutter analyze --no-pub` | No issues found |
| Reviewer preview from actual local API evidence | Rendered and inspected `output/identity-verification/reviewer-identity-checks.png`; all summary values fit 390×844, with responsive 320px/doubled-text coverage |
| Android LAN build and Samsung installation | Debug APK built with the Mac LAN API, installed retaining data and launched; phone API health HTTP200. Compiled artifact contains the compact reviewer title and no old Local-title/Run-action strings |

The backend OCR/face algorithms, authenticated endpoint and encrypted snapshot format are unchanged for this presentation/workflow update. Flutter tests cover applicant hiding for both AWS/local and every check status, ordinary Submit sequencing and duplicate taps, optional failures, stale media/details, authority loss, closure/background and reviewer-only history opt-in. The real-data preview uses the prior live local API result; a full physical-camera-to-review interaction was not rerun for this update. Unrelated shared-checkout changes were preserved separately.
