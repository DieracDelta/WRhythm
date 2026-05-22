#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${TMPDIR:-/tmp}/wrhythm-warning-budget"
mkdir -p "$LOG_DIR"

build_and_capture() {
  local scheme="$1"
  local destination="$2"
  local log_file="$LOG_DIR/${scheme// /_}.log"

  echo "Building $scheme" >&2
  xcodebuild build \
    -project "$ROOT_DIR/WRhythm.xcodeproj" \
    -scheme "$scheme" \
    -destination "$destination" \
    >"$log_file" 2>&1

  echo "$log_file"
}

logs=()
logs+=("$(build_and_capture "WRhythm Watch App" "generic/platform=watchOS Simulator")")
logs+=("$(build_and_capture "WRhythm iPhone" "generic/platform=iOS Simulator")")
logs+=("$(build_and_capture "WRhythm macOS" "platform=macOS")")

source_warnings_file="$LOG_DIR/source-warnings.log"
: >"$source_warnings_file"

for log in "${logs[@]}"; do
  grep -E "\.swift:[0-9]+:[0-9]+: warning:" "$log" >>"$source_warnings_file" || true
done

if [[ -s "$source_warnings_file" ]]; then
  echo "Source warning budget exceeded:"
  cat "$source_warnings_file"
  exit 1
fi

echo "Source warning budget passed. Non-source Xcode/tooling warnings are allowed."
