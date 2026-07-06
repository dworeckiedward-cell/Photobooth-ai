#!/bin/bash
# Boothify 360 — the one-command build+test gate (Blueprint Section 0.1).
# Red output = the phase does NOT advance.
set -o pipefail

DEST="platform=iOS Simulator,name=iPhone 17 Pro"
SCHEME="Photobooth-ai"
cd "$(dirname "$0")/.." || exit 1

echo "▶ GATE: build"
xcodebuild -scheme "$SCHEME" -sdk iphonesimulator -destination "$DEST" build 2>&1 \
  | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -5
BUILD_STATUS=${PIPESTATUS[0]}
if [ "$BUILD_STATUS" -ne 0 ]; then echo "✖ GATE RED: build failed"; exit 1; fi

echo "▶ GATE: tests"
xcodebuild -scheme "$SCHEME" -sdk iphonesimulator -destination "$DEST" test 2>&1 \
  | grep -E "error:|failed|passed|TEST SUCCEEDED|TEST FAILED|Executed" | tail -12
TEST_STATUS=${PIPESTATUS[0]}
if [ "$TEST_STATUS" -ne 0 ]; then echo "✖ GATE RED: tests failed"; exit 1; fi

echo "✔ GATE GREEN"
