#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wrhythm-tests.XXXXXX")"
DERIVED_DATA_DIR="$WORK_DIR/DerivedData"
RESULT_BUNDLE_PATH="$WORK_DIR/WRhythm-macOS.xcresult"

cleanup() {
  if [[ "${KEEP_TEST_ARTIFACTS:-0}" == "1" ]]; then
    echo "Keeping test artifacts at $WORK_DIR"
    return
  fi

  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

cd "$ROOT_DIR"

xcodebuild test \
  -project WRhythm.xcodeproj \
  -scheme "WRhythm macOS" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  "$@"
