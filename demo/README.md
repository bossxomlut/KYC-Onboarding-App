# Demo and recording

The complete main-flow recording with a Vietnamese male voice is [full-flow-voiced.mp4](full-flow-voiced.mp4). The [original silent recording](full-flow.mp4) is also retained. Both use the current Flutter app and real NestJS API, PostgreSQL and Mailpit, with fictional identities from [scenario.json](scenario.json) and illustrated photos in `assets/`. Public passwords in the scenario are for this disposable local demo only.

The video shows registration and email OTP, login, personal details, saved session/progress restoration, document and selfie upload, private previews, editing and retaking, submission, a normal User requesting Reviewer access, super admin approval of that request, reviewer rejection requesting only a new selfie, resubmission, reviewer approval, **Verified**, both historical submissions and logout. Access grants and review decisions are made through authenticated production app screens and persisted by the real API. [Chapter timestamps](full-flow.chapters.json) and [subtitles](full-flow.srt) accompany the MP4.

Three separate fictional accounts are used:

| Account | Email | Identity shown after sign-in |
| --- | --- | --- |
| Applicant | `applicant.demo@kyc.example` | `User` in Account access |
| Reviewer candidate | `reviewer.demo@kyc.example` | `User`, then `Reviewer` after approval, in Account access |
| Super admin | `admin.demo@kyc.example` | Email and `Super admin` on the native admin Home screen |

The reviewer starts as an ordinary User, submits an access request in **Account access**, and receives Reviewer permission only after the super admin confirms approval in **Manage accounts**. The recording then opens **Review profiles** from both Home and Account access. Each switch shows the sign-in email and the corresponding native identity screen. The runner rejects equal account emails regardless of letter case. In the reviewer queue, a profile-row email belongs to the applicant being reviewed.

Personal details, saved progress, uploaded images, access requests/grants, submitted snapshots, review decisions and history are persisted on the server. The app loads and displays that state; its secure refresh credential and temporary capture/retry files have a separate device lifecycle.

Milestones pause for four seconds by default. Forms and photo previews remain visible for six seconds; account identities, important statuses and access/review decisions remain visible for eight seconds. These holds let viewers read the screens while the male narration runs ten percent slower.

## Vietnamese voiceover

The narrated version adds **25 passages** using **`vi-VN-NamMinhNeural`**, a Vietnamese male voice listed in [Microsoft's voice documentation](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts), through [`edge-tts`](https://github.com/rany2/edge-tts), with speech rate **`-10%`**. It preserves the original video stream, duration and chapters, and adds an AAC Vietnamese audio track. [Vietnamese subtitles](full-flow.vi.srt), the editable [narration plan](voiceover.vi.json) and the [timing report](voiceover.vi.report.json) are included.

To rebuild the narration with Python, FFmpeg/FFprobe and internet access, run from the repository root:

```sh
python3 -m venv demo/.runtime/tts-venv
demo/.runtime/tts-venv/bin/python -m pip install -r demo/tts-requirements.txt
python3 demo/add-voiceover.py
```

The requirements pin `edge-tts==7.2.8`. Speech synthesis sends only the fictional narration text to Microsoft Edge's online speech service. The video, illustrated documents and server records stay in the isolated demo environment on the Mac. No API key is required by this library.

Edit the text and chapter anchors in `demo/voiceover.vi.json` to change the narration. Each start/end anchor specifies a chapter slug, occurrence and offset; timings resolve automatically from `demo/full-flow.chapters.json` after a new recording. The script checks that speech fits its screen interval, normalizes volume and reports any applied speed adjustment. Temporary audio stays in ignored `demo/.runtime/voiceover/`.

## Reproduce the recording

On macOS, install the repository dependencies, Flutter/Xcode, FFmpeg and Mailpit, then boot an iOS Simulator. Mailpit can be on `PATH` or at `backend/.local/tools/mailpit/mailpit`. From the repository root:

```sh
python3 demo/record-full-flow.py
# Select a specific booted simulator when necessary:
python3 demo/record-full-flow.py --device DEVICE_ID
```

The runner starts a disposable PostgreSQL database on port **55462**, a separate API on **3300** and Mailpit on **8125/1125**, then runs `mobile/integration_test/recording_main_flow_test.dart`. It does not read `backend/.env` or touch the normal development database. Runtime data and logs stay in ignored `demo/.runtime/`; raw `demo/full-flow.mov` is ignored. Only `@kyc.example` recipients are allowed. The recorder starts after the app is ready, so the delivered video excludes build output and the desktop.

iOS Simulator has no camera. This recording substitutes only camera capture with the clearly marked synthetic illustrations; it demonstrates upload and review, not physical lens capture, liveness or document authenticity. Session restoration recreates the app/container while retaining its secure refresh credential. Optional OCR/face checks are outside this main-flow recording.

## Manual recording checklist

1. Follow the [local setup guide](../docs/local-setup.md). To start with no old accounts or profiles, use its [data reset steps](../docs/local-setup.md#9-xoá-toàn-bộ-dữ-liệu-local-và-chạy-lại-từ-đầu).
2. Start PostgreSQL, Mailpit and the real NestJS API. Bootstrap the super admin and use three distinct fictional emails for the applicant, reviewer candidate and admin.
3. Use an Android emulator with a camera or a physical Android/iPhone for the production capture flow. iOS Simulator has no real camera; the integration test below substitutes synthetic capture only.
4. Start screen recording. Register with a fictional `@kyc.example` email, verify the Mailpit OTP and sign in.
5. Save personal details, then close/reopen the app to show saved progress and session restoration. Continue the interrupted KYC flow.
6. Capture a synthetic identity document and a selfie, review the private images, demonstrate edit/retake, and submit. Show **Pending review**.
7. Sign in as the reviewer candidate while its role is still **User** and request Reviewer access. Sign in as the super admin, open **Manage accounts**, review the pending request and confirm approval. Sign back in as the reviewer and show its new role.
8. Open **Review profiles** from Home, return, then open it from Account access. In the queue, select the applicant, reject with a reason and request a selfie resubmission.
9. Return to the applicant, refresh, replace only the requested photo and submit again; accepted information and images remain on the server.
10. Approve as the reviewer, refresh the applicant result, show **Verified**, both historical submissions, then logout and stop recording.

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
