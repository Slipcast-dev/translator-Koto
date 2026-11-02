#!/bin/bash
# Обновление проверяется на реальных DMG и процессах; GitHub не используется, транспорт подменён.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT_DIR/build/DerivedData/Build/Products/Release/Koto.app}"
[[ -d "$APP" ]] || { echo "Сначала соберите Release или передайте путь к Koto.app" >&2; exit 2; }
mkdir -p "$ROOT_DIR/build/update-tests"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macosx26.0 \
    "$ROOT_DIR/Services/Update/UpdateService.swift" "$ROOT_DIR/Services/Update/UpdateModel.swift" \
    "$ROOT_DIR/Support/PrivateStorage.swift" "$ROOT_DIR/Tests/UpdateTests.swift" \
    -o "$ROOT_DIR/build/update-tests/update-tests"
"$ROOT_DIR/build/update-tests/update-tests" "$APP"
