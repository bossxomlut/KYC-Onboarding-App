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
