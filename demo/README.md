# Synthetic end-to-end demo

The delivered recording is `full-flow.mp4` (about 46 seconds), recorded against the compiled NestJS 12.1.2 API with real PostgreSQL and Mailpit. The raw simulator recording is kept locally as `full-flow.mov` and includes build/startup time. The delivered MP4 removes that idle prefix and preserves the full test flow.

`document.jpg` and `selfie.jpg` in `assets/` are generated illustrations marked **DEMO / NOT VALID**. Names, document number, address and email are fictional. `mobile/integration_test/demo_fixtures.dart` embeds the JPEGs only in the integration-test target; the normal app always uses the real device camera.

The automated recording exercises the **real running NestJS backend, SMTP catcher, PostgreSQL, session rotation, encrypted private media and reviewer transitions**. Only camera capture is substituted because iOS Simulator cannot take a real photograph. One upload request is deliberately interrupted before transmission to demonstrate retained capture and retry. Reviewer decisions come from a privileged test coordinator calling the same server review function as the local CLI; the app has no reviewer control or demo verification endpoint.

1. Start API/PostgreSQL/Mailpit using the root README.
2. Boot an iOS Simulator. Get its ID with `flutter devices` or `xcrun simctl list devices booted`.
3. From the repository root, run:

```sh
./scripts/record-demo.sh <BOOTED_SIMULATOR_UUID>
```

The script creates a unique synthetic account, runs the test coordinator, records the simulator and stops its recording processes on exit. It writes `demo/full-flow.mov`. The database retains this demo account/history; it does not delete anyone’s existing data. A retry uses a new email and does not need a database reset.

The flow shows registration/OTP, Home progress, personal details, whole-app re-creation with refresh-token restoration, a failed document upload and retry, selfie, review of private images, submission, rejection with reason, selfie-only resubmission, verified result and logout. Whole-app re-creation proves server draft/session recovery, while Android lost-camera process recovery is covered by focused data tests. A force-kill/physical-camera manual check is separate.

To run without recording, start the privileged reviewer coordinator in another terminal with a unique `@kyc.example` email:

```sh
cd backend
./node_modules/.bin/tsx ../scripts/demo-review.mts recording-unique@kyc.example
# Another terminal, repository/mobile:
flutter test integration_test/real_api_flow_test.dart -d <SIMULATOR_UUID> \
  --dart-define=DEMO_EMAIL=recording-unique@kyc.example \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1 \
  --dart-define=MAILPIT_URL=http://127.0.0.1:8025
```

For an Android emulator use `10.0.2.2` for both API and Mailpit hosts. For a real phone, manually capture a printed synthetic document and a demo subject’s face with consent; do not show a real ID or OTP/reset credentials in any shared video. Test fixtures can be regenerated with `python3 scripts/generate-demo-fixtures.py` (Pillow is only needed when regenerating source JPEGs).
