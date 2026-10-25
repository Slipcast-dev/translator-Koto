#!/bin/bash
# Проверки локализации не загружают модель и не читают личные настройки.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/localization"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -target arm64-apple-macosx26.0 \
    "$ROOT_DIR"/Core/Translation/*.swift \
    "$ROOT_DIR/Core/Migration/SettingsMigration.swift" \
    "$ROOT_DIR"/Services/Local/*.swift \
    "$ROOT_DIR/Tests/LocalizationDynamicsTests.swift" \
    -o "$ROOT_DIR/build/localization/dynamics-tests"
"$ROOT_DIR/build/localization/dynamics-tests"
