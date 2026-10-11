# Demo and recording

Record the current app manually and save the final short video as `demo/full-flow.mp4`. The previous recording and automatic recording script were removed during repository cleanup. The final MP4 can be committed when ready; raw `.mov` files are ignored.

## Manual recording checklist

1. Follow the [local setup guide](../docs/local-setup.md). To start with no old accounts or profiles, use its [data reset steps](../docs/local-setup.md#9-xoá-toàn-bộ-dữ-liệu-local-và-chạy-lại-từ-đầu).
2. Start PostgreSQL, Mailpit and the real NestJS API. Bootstrap the super admin; keep a separate admin/reviewer session ready to make review decisions.
3. Use an Android emulator with a camera or a physical Android/iPhone for the production capture flow. iOS Simulator has no real camera; the integration test below substitutes synthetic capture only.
4. Start screen recording. Register with a fictional `@kyc.example` email, verify the Mailpit OTP and sign in.
5. Save personal details, then close/reopen the app to show saved progress and session restoration. Continue the interrupted KYC flow.
6. Capture a synthetic identity document and a selfie, review the private images, demonstrate edit/retake, and submit. Show **Pending review**.
7. As the reviewer, reject with a reason and request a selfie resubmission. Return to the applicant, refresh, replace the requested photo and submit again; accepted steps remain saved.
8. Approve as the reviewer, refresh the applicant result, show **Verified**, then logout and stop recording.

Use a printed synthetic document or display the sample on another screen. Do not record a real identity document. Keep admin passwords and configuration files outside the recording. Optional OCR/face checks assist review; a synthetic document portrait may differ from the demo subject's selfie.

## Synthetic assets

`assets/document.jpg` and `assets/selfie.jpg` are illustrations marked **DEMO / NOT VALID**. Their identity details are fictional. `assets/cccd_mau.png` is an additional Vietnamese test document marked **MẪU TEST / DỮ LIỆU GIẢ LẬP** for manual capture.

`mobile/integration_test/demo_fixtures.dart` embeds the JPEG fixtures only in the integration-test target. The normal app uses the device camera. Regenerate the embedded fixtures with:

```sh
python3 scripts/generate-demo-fixtures.py
```

The embedding script uses only Python's standard library.

## Real-API integration test

Keep the API, PostgreSQL and Mailpit running. Use a unique email for each test run. In a terminal at the repository root:

```sh
cd backend
./node_modules/.bin/tsx ../scripts/demo-review.mts recording-unique@kyc.example
```

In another terminal at `mobile`:

```sh
flutter test integration_test/real_api_flow_test.dart -d "DEVICE_ID" \
  --dart-define=DEMO_EMAIL=recording-unique@kyc.example \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1 \
  --dart-define=MAILPIT_URL=http://127.0.0.1:8025
```

Use the ID from `flutter devices`. The URLs above are for iOS Simulator; for an Android emulator use `10.0.2.2` for both hosts. Stop the coordinator with `Ctrl+C` when finished.

The test calls the real running backend for registration/OTP, session restoration, saved resume, failed-upload retry, private review, submission, rejection, selfie-only resubmission, approval and logout. The privileged local coordinator drives review decisions as a synthetic reviewer; normal users review through authenticated app screens. Only platform camera capture is substituted. The test creates synthetic database records and does not delete existing accounts.
