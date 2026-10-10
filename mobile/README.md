# Flutter client

Use the [complete macOS setup guide in Vietnamese](../docs/local-setup.md) for tool installation, API/database/email setup, device-specific run commands and restarting services. The [repository root README](../README.md) also describes architecture, tests and demo commands.

Feature boundaries: `lib/features/auth` and `lib/features/kyc` each contain pure domain, IO/mapping data, and use-case-driven presentation layers. `lib/app` composes DI and navigation. `lib/core` contains network, secure token storage and Material 3 design tokens.

Run `flutter pub get`, `flutter analyze`, and `flutter test` from this directory. The running app always uses the real backend; only automated tests substitute platform camera/media capture with synthetic fixtures.
