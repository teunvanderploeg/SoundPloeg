#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "[preflight] Model catalog consistency"
cmp Config/model_catalog.json Sources/SoundPloegInfra/Resources/model_catalog.json

echo "[preflight] Swift build"
swift build

echo "[preflight] Swift test"
swift test

echo "[preflight] Xcode project generation"
./Scripts/generate_xcodeproj.sh

echo "[preflight] OK"
