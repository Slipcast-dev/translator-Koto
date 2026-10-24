#!/bin/bash
# Настоящий runtime, модель и HTTP; внешние API не используются.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/stage4"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -target arm64-apple-macosx26.0 \
    "$ROOT_DIR"/Core/Translation/*.swift "$ROOT_DIR"/Services/Local/*.swift \
    "$ROOT_DIR/Tests/LocalTranslationProbe.swift" -o "$ROOT_DIR/build/stage4/local-translation-probe"
"$ROOT_DIR/build/stage4/local-translation-probe" "$ROOT_DIR/Resources" "$@"
