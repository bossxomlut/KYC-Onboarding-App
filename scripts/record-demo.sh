#!/usr/bin/env bash
set -euo pipefail
simulator_id="${1:?Pass a booted iOS Simulator device ID}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
mkdir -p demo tmp
review_pid=''
record_pid=''
cleanup() {
  if [[ -n "$record_pid" ]]; then
    kill -INT "$record_pid" 2>/dev/null || true
    wait "$record_pid" 2>/dev/null || true
  fi
  if [[ -n "$review_pid" ]]; then
    kill "$review_pid" 2>/dev/null || true
    wait "$review_pid" 2>/dev/null || true
  fi
  xcrun simctl status_bar "$simulator_id" clear
}
trap cleanup EXIT
# Requires running API, PostgreSQL, Mailpit and this booted iOS Simulator.
xcrun simctl status_bar "$simulator_id" override --time '9:41' --batteryState charged --batteryLevel 100
demo_email="recording-$(date +%s)@kyc.example"
(cd backend && ./node_modules/.bin/tsx ../scripts/demo-review.mts "$demo_email") &
review_pid=$!
printf '%s\n' "$demo_email" > tmp/recording-email
# Fail early if the reviewer process could not load its configuration.
sleep 1
kill -0 "$review_pid"
xcrun simctl io "$simulator_id" recordVideo --force --codec=h264 tmp/raw-demo.mov &
record_pid=$!
cd mobile
flutter test integration_test/real_api_flow_test.dart -d "$simulator_id" \
  --dart-define=DEMO_EMAIL="$demo_email" \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1 \
  --dart-define=MAILPIT_URL=http://127.0.0.1:8025
cd "$repo_root"
cleanup
trap - EXIT
mv tmp/raw-demo.mov demo/full-flow.mov
