#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# Use Flutter's bundled Dart even when a standalone SDK appears first in PATH.
flutter_sdk_bin="$(node -e 'process.stdout.write(require("node:path").dirname(require("node:fs").realpathSync(process.argv[1])))' "$(command -v flutter)")"
export PATH="$flutter_sdk_bin:$PATH"
cd "$repo_root/backend"
npm run check
npm test
cd "$repo_root/mobile"
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
