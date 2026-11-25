#!/bin/bash
# Регрессии аудита: хранилище, словарь, живой перевод, очередь модели, сочетания, мост и замена приложения.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/regression-tests"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macosx26.0 \
    "$ROOT_DIR"/Core/Translation/*.swift "$ROOT_DIR"/Core/Capture/*.swift "$ROOT_DIR"/Core/Bridge/*.swift \
    "$ROOT_DIR/Support/PrivateStorage.swift" "$ROOT_DIR/Services/Product/TranslationStore.swift" \
    "$ROOT_DIR/Services/Product/GlossaryExchange.swift" "$ROOT_DIR"/Services/Local/*.swift \
    "$ROOT_DIR/Services/Capture/ScreenOCRService.swift" "$ROOT_DIR/Services/Update/UpdateService.swift" \
    "$ROOT_DIR/Features/Live/QuickTranslator.swift" "$ROOT_DIR/Tests/RegressionTests.swift" \
    -o "$ROOT_DIR/build/regression-tests/regression-tests"
"$ROOT_DIR/build/regression-tests/regression-tests"
