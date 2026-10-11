# Flutter client

Use the [complete macOS setup guide in Vietnamese](../docs/local-setup.md) for tool installation, API/database/email setup, device-specific run commands and restarting services. The [repository root README](../README.md) also describes architecture, tests and demo commands.

Feature boundaries: `lib/features/auth` and `lib/features/kyc` each contain pure domain, IO/mapping data, and use-case-driven presentation layers. `lib/app` composes DI and navigation. `lib/core` contains network, secure token storage and Material 3 design tokens.

Run `flutter pub get`, `flutter analyze`, and `flutter test` from this directory. The running app always uses the real backend; only automated tests substitute platform camera/media capture with synthetic fixtures.

Document and selfie capture use an in-app camera with framing overlays. Documents require a rear camera; selfies require a front camera. Document photos are cropped to the visible frame with a 3% margin on each edge, correcting orientation and preview scaling before private saving, preview, recovery or upload. Selfies keep their original bytes. Only camera permission is needed for photo capture. Permission and unavailable-camera errors offer Retry, and leaving the camera or backgrounding releases its resources. Photos are saved privately before upload; upload retry and explicit Continue retain the existing flow.

To exercise both real lenses, background/resume, private persistence and recovery on an Android emulator or device with camera permission, run `flutter test integration_test/in_app_camera_smoke_test.dart -d DEVICE_ID`. This camera-only test does not need the API or an account. iOS Simulator has no camera; use a physical iPhone for this test. To render the camera layouts with a synthetic preview, run `flutter test tool/render_in_app_camera_test.dart`; PNGs are written to `../output/in-app-camera/`.
