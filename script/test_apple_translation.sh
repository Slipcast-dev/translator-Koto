#!/bin/bash
# Отдельный smoke реального движка; требует уже установленные системные языковые ресурсы.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/stage2"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -target arm64-apple-macosx26.0 \
    "$ROOT_DIR"/Core/Translation/*.swift \
    "$ROOT_DIR/Services/Translation/AppleTranslationEngine.swift" \
    "$ROOT_DIR/Tests/AppleTranslationProbe.swift" \
    -o "$ROOT_DIR/build/stage2/apple-translation-probe"
"$ROOT_DIR/build/stage2/apple-translation-probe"
