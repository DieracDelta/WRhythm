#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d /tmp/wrhythm-tier2-sync.XXXXXX)"
CREATED_SIMULATORS_FILE="$TMP_ROOT/created-simulators.txt"
: > "$CREATED_SIMULATORS_FILE"

cleanup() {
  local status=$?

  while IFS= read -r udid; do
    [[ -n "$udid" ]] || continue
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
  done < "$CREATED_SIMULATORS_FILE"

  rm -rf "$TMP_ROOT"
  exit "$status"
}
trap cleanup EXIT

run_with_timeout() {
  local seconds="$1"
  shift

  "$@" &
  local pid=$!
  local elapsed=0

  while kill -0 "$pid" >/dev/null 2>&1; do
    if (( elapsed >= seconds )); then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 2
      kill -9 "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
}

select_runtime() {
  local platform="$1"
  local runtimes_json="$TMP_ROOT/runtimes.json"

  xcrun simctl list runtimes -j > "$runtimes_json"
  /usr/bin/python3 - "$platform" "$runtimes_json" <<'PY'
import json
import sys

platform = sys.argv[1]
json_path = sys.argv[2]
with open(json_path) as handle:
    data = json.load(handle)

runtimes = [
    runtime for runtime in data["runtimes"]
    if runtime.get("isAvailable") and runtime.get("platform") == platform
]
if not runtimes:
    raise SystemExit(f"No available {platform} simulator runtime")

def version_key(runtime):
    return tuple(int(piece) for piece in runtime["version"].split("."))

print(max(runtimes, key=version_key)["identifier"])
PY
}

select_device_type() {
  local product_family="$1"
  local preferred_name="$2"
  local devicetypes_json="$TMP_ROOT/devicetypes.json"

  xcrun simctl list devicetypes -j > "$devicetypes_json"
  /usr/bin/python3 - "$product_family" "$preferred_name" "$devicetypes_json" <<'PY'
import json
import sys

product_family = sys.argv[1]
preferred_name = sys.argv[2]
json_path = sys.argv[3]
with open(json_path) as handle:
    data = json.load(handle)

matches = [
    device for device in data["devicetypes"]
    if device.get("productFamily") == product_family
]
if not matches:
    raise SystemExit(f"No simulator device types for {product_family}")

preferred = [device for device in matches if device["name"] == preferred_name]
print((preferred or matches)[0]["identifier"])
PY
}

create_and_boot_simulator() {
  local name="$1"
  local device_type="$2"
  local runtime="$3"
  local udid

  udid="$(xcrun simctl create "$name" "$device_type" "$runtime")"
  echo "$udid" >> "$CREATED_SIMULATORS_FILE"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  echo "$udid"
}

run_sync_tests() {
  local label="$1"
  local scheme="$2"
  local destination="$3"
  local only_testing="$4"
  local derived_data="$5"
  local result_bundle="$6"
  local log_file="$7"

  echo "Running $label sync tests..."
  local exit_code=0
  run_with_timeout "${TEST_TIMEOUT_SECONDS:-2700}" xcodebuild test \
    -project "$ROOT_DIR/WRhythm.xcodeproj" \
    -scheme "$scheme" \
    -destination "$destination" \
    -destination-timeout 60 \
    -parallel-testing-enabled NO \
    -maximum-concurrent-test-simulator-destinations 1 \
    -only-testing:"$only_testing" \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$result_bundle" \
    CODE_SIGNING_ALLOWED=NO > "$log_file" 2>&1 || exit_code=$?

  if (( exit_code != 0 )); then
    if (( exit_code == 124 )); then
      echo "$label sync tests timed out before completion."
    fi
    echo "$label sync tests failed. Last 120 log lines:"
    tail -n 120 "$log_file" || true
    echo ""
    echo "$label xcresult summary:"
    xcrun xcresulttool get test-results tests --path "$result_bundle" 2>/dev/null || true
    return 1
  fi

  echo "$label sync tests passed."
}

delete_simulator() {
  local udid="$1"
  [[ -n "$udid" ]] || return 0
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$udid" >/dev/null 2>&1 || true
}

run_simulator_sync_tests() {
  local label="$1"
  local scheme="$2"
  local platform="$3"
  local device_type="$4"
  local runtime="$5"
  local only_testing="$6"
  local derived_data="$7"
  local result_bundle="$8"
  local log_file="$9"
  local udid

  udid="$(create_and_boot_simulator "WRhythm Tier2 Sync $label $$" "$device_type" "$runtime")"
  if ! run_sync_tests \
    "$label" \
    "$scheme" \
    "platform=$platform,id=$udid" \
    "$only_testing" \
    "$derived_data" \
    "$result_bundle" \
    "$log_file"; then
    delete_simulator "$udid"
    return 1
  fi
  delete_simulator "$udid"
}

echo "== WRhythm Tier 2 simulator sync tests =="
echo "Temporary artifacts: $TMP_ROOT"

IOS_RUNTIME="${IOS_RUNTIME:-$(select_runtime iOS)}"
WATCH_RUNTIME="${WATCH_RUNTIME:-$(select_runtime watchOS)}"
IPHONE_TYPE="${IPHONE_TYPE:-$(select_device_type iPhone "iPhone 17 Pro")}"
WATCH_TYPE="${WATCH_TYPE:-$(select_device_type "Apple Watch" "Apple Watch SE 3 (40mm)")}"

if [[ "${RUN_IPHONE:-1}" == "1" ]]; then
  run_simulator_sync_tests \
    "iPhone simulator" \
    "WRhythm iPhone" \
    "iOS Simulator" \
    "$IPHONE_TYPE" \
    "$IOS_RUNTIME" \
    "WRhythm iPhoneTests/PlaybackSyncPolicyTests" \
    "$TMP_ROOT/DerivedData-iPhone" \
    "$TMP_ROOT/iphone-sync.xcresult" \
    "$TMP_ROOT/iphone-sync.log"
fi

if [[ "${RUN_WATCH:-1}" == "1" ]]; then
  run_simulator_sync_tests \
    "watchOS simulator" \
    "WRhythm Watch App" \
    "watchOS Simulator" \
    "$WATCH_TYPE" \
    "$WATCH_RUNTIME" \
    "WRhythm Watch AppTests/PlaybackSyncPolicyTests" \
    "$TMP_ROOT/DerivedData-watch" \
    "$TMP_ROOT/watch-sync.xcresult" \
    "$TMP_ROOT/watch-sync.log"
fi

if [[ "${RUN_MACOS:-1}" == "1" ]]; then
  run_sync_tests \
    "macOS host" \
    "WRhythm macOS" \
    "platform=macOS" \
    "WRhythm macOSTests/PlaybackSyncPolicyTests" \
    "$TMP_ROOT/DerivedData-macOS" \
    "$TMP_ROOT/macos-sync.xcresult" \
    "$TMP_ROOT/macos-sync.log"
fi

echo "Tier 2 simulator sync tests passed."
