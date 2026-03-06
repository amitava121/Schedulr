#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT_PATH="Schedulr.xcodeproj"
DEFAULT_SCHEME="Schedulr"
DESTINATION_GENERIC_IOS="generic/platform=iOS"
LOGIC_PACKAGE_DIR="LogicTestsPackage"

log() {
  echo "\n[$(date +"%H:%M:%S")] $*"
}

run_cmd() {
  log "$*"
  "$@"
}

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Project not found at: $PROJECT_PATH"
  exit 1
fi

if [[ -f "$LOGIC_PACKAGE_DIR/Package.swift" ]]; then
  log "Running Swift Package logic tests"
  run_cmd swift test --package-path "$LOGIC_PACKAGE_DIR"
else
  log "No Swift Package logic tests found at $LOGIC_PACKAGE_DIR. Skipping swift test."
fi

log "Collecting project/scheme metadata"
LIST_OUTPUT="$(xcodebuild -list -project "$PROJECT_PATH")"
printf "%s\n" "$LIST_OUTPUT"

HAS_TEST_TARGETS="false"
if grep -q 'com.apple.product-type.bundle.unit-test' "$PROJECT_PATH/project.pbxproj" || grep -q 'com.apple.product-type.bundle.ui-testing' "$PROJECT_PATH/project.pbxproj"; then
  HAS_TEST_TARGETS="true"
fi

log "Running compile-only build (no code signing, no simulator/device)"
run_cmd xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$DEFAULT_SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION_GENERIC_IOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

log "Running static analyzer"
run_cmd xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$DEFAULT_SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION_GENERIC_IOS" \
  CODE_SIGNING_ALLOWED=NO \
  analyze

if [[ "$HAS_TEST_TARGETS" == "true" ]]; then
  log "Detected test target(s). Attempting simulator-based xcodebuild test if an iOS simulator is available."

  SIM_DEST="$(xcrun simctl list devices available | grep -E 'iPhone .*\(.*\) \(Shutdown\)|iPhone .*\(.*\) \(Booted\)' | head -n 1 | sed -E 's/.*\(([-A-F0-9]+)\).*/id=\1/')"

  if [[ -n "${SIM_DEST:-}" ]]; then
    run_cmd xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$DEFAULT_SCHEME" \
      -configuration Debug \
      -destination "$SIM_DEST" \
      test
  else
    log "No available iOS simulator found. Skipping xcodebuild test step."
  fi
else
  log "No XCTest targets detected in project. Skipping xcodebuild test step."
fi

log "All possible automated checks completed successfully."
