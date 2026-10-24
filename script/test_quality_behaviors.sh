#!/bin/bash
# Проверяем потерю текста и цитатные gates отдельно от вероятностной модели.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/quality"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macosx26.0 \
 "$ROOT_DIR"/Core/Translation/*.swift "$ROOT_DIR"/Services/Local/*.swift \
 "$ROOT_DIR/Tests/QualityBehaviorTests.swift" -o "$ROOT_DIR/build/quality/behavior-tests"
"$ROOT_DIR/build/quality/behavior-tests"
