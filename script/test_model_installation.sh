#!/bin/bash
# Изолированные temporary fixtures: не загружает реальные веса и не меняет App Support пользователя.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/models"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macosx26.0 \
 "$ROOT_DIR"/Core/Translation/*.swift "$ROOT_DIR"/Services/Local/*.swift \
 "$ROOT_DIR/Support/PrivateStorage.swift" "$ROOT_DIR"/Services/Models/*.swift \
 "$ROOT_DIR/Tests/ModelInstallationTests.swift" -o "$ROOT_DIR/build/models/model-installation-tests"
"$ROOT_DIR/build/models/model-installation-tests"
