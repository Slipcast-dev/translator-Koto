#!/bin/bash
# Контракты захвата, реальный именованный pasteboard и Vision на синтетическом изображении.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/stage3"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -target arm64-apple-macosx26.0 \
    "$ROOT_DIR"/Core/Translation/*.swift \
    "$ROOT_DIR/Core/Capture/CaptureModels.swift" \
    "$ROOT_DIR/Services/Capture/CaptureServiceProvider.swift" \
    "$ROOT_DIR/Services/Capture/ScreenOCRService.swift" \
    "$ROOT_DIR/Tests/CaptureTests.swift" \
    -o "$ROOT_DIR/build/stage3/capture-tests"
"$ROOT_DIR/build/stage3/capture-tests"
