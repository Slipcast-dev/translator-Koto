#!/bin/bash
# Общая точка локального запуска и GitHub CI. Веса и разрешения экрана не нужны.
# Scheme содержит приложение без XCTest target; проверки — отдельные @main harness.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for harness in manual_translation product_privacy capture runtime_transport quality_behaviors model_installation bridge_protocol localization_dynamics cloud_policy; do
    bash "$ROOT_DIR/script/test_${harness}.sh"
done
mkdir -p "$ROOT_DIR/build/ci-tests"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macosx26.0 \
    "$ROOT_DIR/Core/Live/LiveFrameGate.swift" "$ROOT_DIR/Tests/LiveFrameTests.swift" \
    -o "$ROOT_DIR/build/ci-tests/live-tests"
"$ROOT_DIR/build/ci-tests/live-tests"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macosx26.0 \
    "$ROOT_DIR"/Core/Translation/*.swift "$ROOT_DIR/Core/Migration/SettingsMigration.swift" \
    "$ROOT_DIR/Tests/SettingsMigrationTests.swift" -o "$ROOT_DIR/build/ci-tests/migration-tests"
"$ROOT_DIR/build/ci-tests/migration-tests"

# Native host должен соответствовать текущему исходному helper выбора socket path.
bash "$ROOT_DIR/script/build_native_host.sh"
python3 "$ROOT_DIR/script/test_bridge_long_path.py"
