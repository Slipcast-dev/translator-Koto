#!/bin/bash
# Проверяем настоящую state machine приложения; подменяется только граница внешнего engine.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/stage2"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -target arm64-apple-macosx26.0 \
    "$ROOT_DIR"/Core/Translation/*.swift \
    "$ROOT_DIR/Features/ManualTranslation/ManualTranslationModel.swift" \
    "$ROOT_DIR/Tests/ManualTranslationTests.swift" \
    -o "$ROOT_DIR/build/stage2/manual-translation-tests"
"$ROOT_DIR/build/stage2/manual-translation-tests"
