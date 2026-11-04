#!/bin/bash
# Runs the iPhone UI tests against a real Spoonmate server: builds the Docker image, starts a throwaway container on a
# free localhost port, seeds it with tools/seed_demo.py, boots the simulator and runs the RecipeManagerUITests scheme.
# The container and its data are removed on exit, whatever happens.
#
#   IOS/scripts/run-ui-tests.sh                 # the UI tests (SpoonmateFlowTests)
#   IOS/scripts/run-ui-tests.sh --screenshots   # retake docs/screenshots/ios and the App Store raw captures instead
#
# SIMULATOR_ID picks another simulator (default: the iPhone 17 Pro, iOS 26.5, on the main dev Mac).
set -euo pipefail

SIM="${SIMULATOR_ID:-5B03F88E-6FEE-4427-9A6B-5A3B104C509E}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IOS="$ROOT/IOS"
IMAGE=spoonmate-test
NAME="spoonmate-uitest-$$"
USERNAME=Alex
PASSWORD=Spoonmate-demo-1          # both made by tools/seed_demo.py
MODE=tests
[[ "${1:-}" == "--screenshots" ]] && MODE=screenshots

DERIVED="$(mktemp -d "${TMPDIR:-/tmp}/spoonmate-uitest-build.XXXXXX")"
SHOTS="$(mktemp -d "${TMPDIR:-/tmp}/spoonmate-shots.XXXXXX")"

cleanup() {
  docker rm -fv "$NAME" >/dev/null 2>&1 || true   # -v: the data volume goes too
  rm -rf "$DERIVED" "$SHOTS"
  if [[ "$MODE" == screenshots ]]; then xcrun simctl status_bar "$SIM" clear >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT INT TERM

echo "==> Building the server image"
docker build -q -t "$IMAGE" "$ROOT" >/dev/null

echo "==> Starting a throwaway server"
# The data lives in an anonymous volume (removed with the container). Not a bind mount: SQLite on a macOS bind mount
# gives "disk I/O error" under the server's workers.
docker run -d --name "$NAME" -p 127.0.0.1::5000 -v /app/data "$IMAGE" >/dev/null
PORT="$(docker port "$NAME" 5000/tcp | head -1 | sed 's/.*://')"
SERVER="http://127.0.0.1:$PORT"
for _ in $(seq 1 60); do
  curl -fsS "$SERVER/api/v1/site" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "$SERVER/api/v1/site" >/dev/null || { echo "The server didn't start"; docker logs "$NAME"; exit 1; }

echo "==> Seeding $SERVER"
# The image has Pillow but leaves tools/ out, so the seeder is copied in and run against the container's own port.
docker cp "$ROOT/tools/seed_demo.py" "$NAME:/tmp/seed_demo.py"
docker exec "$NAME" python /tmp/seed_demo.py http://127.0.0.1:5000

echo "==> Booting the simulator"
xcrun simctl bootstatus "$SIM" -b >/dev/null

cd "$IOS"
xcodegen generate --quiet

# Signed ad hoc (no team): the app keeps its sign-in in the Keychain, which an unsigned simulator build can't use,
# and the offline test relaunches the app.
SIGNING=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)

run_tests() {   # $1: the test class. The full log is kept in $DERIVED/<class>.log while the script runs.
  local log="$DERIVED/$1.log" status
  set +e
  # TEST_RUNNER_* variables reach the test process without the prefix (see RecipeManagerUITests/UITestSupport.swift).
  TEST_RUNNER_SPOONMATE_TEST_SERVER="$SERVER" \
  TEST_RUNNER_SPOONMATE_TEST_USERNAME="$USERNAME" \
  TEST_RUNNER_SPOONMATE_TEST_PASSWORD="$PASSWORD" \
  TEST_RUNNER_SPOONMATE_SCREENSHOTS_DIR="$SHOTS" \
  xcodebuild test -project RecipeManager.xcodeproj -scheme RecipeManagerUITests \
    -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DERIVED" \
    -only-testing:"RecipeManagerUITests/$1" "${SIGNING[@]}" 2>&1 \
    | tee "$log" | grep --line-buffered -E "^Test Case|error:|Executed|\*\* TEST|Failing tests"
  status=${PIPESTATUS[0]}
  set -e
  return "$status"
}

if [[ "$MODE" == tests ]]; then
  echo "==> Running the UI tests"
  run_tests SpoonmateFlowTests
  exit 0
fi

echo "==> Taking screenshots"
xcrun simctl ui "$SIM" appearance light
xcrun simctl status_bar "$SIM" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100
run_tests ScreenshotTests

# Raw captures for the App Store slides (1206x2622), then the README set at half size (600x1304).
RAW="$IOS/AppStore/Screenshots/raw"
DOCS="$ROOT/docs/screenshots/ios"
shopt -s nullglob
for f in "$SHOTS"/appstore-*.png; do cp "$f" "$RAW/${f##*/appstore-}"; done
for f in "$SHOTS"/docs-*.png; do sips -z 1304 600 "$f" --out "$DOCS/${f##*/docs-}" >/dev/null; done
echo "==> Framing the App Store slides"
(cd "$IOS/AppStore/Screenshots" && ./generate.sh)
echo "Screenshots written to $DOCS and $IOS/AppStore/Screenshots"
