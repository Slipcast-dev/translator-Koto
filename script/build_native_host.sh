#!/bin/bash
# Host и desktop используют одну схему и закреплённый публичный origin.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/Resources/BrowserBridge"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -O -target arm64-apple-macosx26.0 "$ROOT_DIR"/Core/Bridge/*.swift \
    "$ROOT_DIR/Support/PrivateStorage.swift" "$ROOT_DIR/NativeHost/HostMain.swift" \
    -o "$ROOT_DIR/Resources/BrowserBridge/koto-native-host"
codesign --force --sign - "$ROOT_DIR/Resources/BrowserBridge/koto-native-host"
