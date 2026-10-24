#!/bin/bash
# Контрактные тесты и реальная AF_UNIX-служба с Apple Translation для integration.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/stage5" "$ROOT_DIR/Docs/validation"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -target arm64-apple-macosx26.0 "$ROOT_DIR"/Core/Bridge/*.swift \
    "$ROOT_DIR/Support/PrivateStorage.swift" "$ROOT_DIR/Tests/BridgeProtocolTests.swift" \
    -o "$ROOT_DIR/build/stage5/bridge-protocol-tests"
"$ROOT_DIR/build/stage5/bridge-protocol-tests"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -target arm64-apple-macosx26.0 "$ROOT_DIR"/Core/Bridge/*.swift "$ROOT_DIR"/Core/Translation/*.swift \
    "$ROOT_DIR/Support/PrivateStorage.swift" "$ROOT_DIR"/Services/Translation/*.swift \
    "$ROOT_DIR"/Services/Cloud/*.swift "$ROOT_DIR/Services/Product/TranslationStore.swift" \
    "$ROOT_DIR"/Services/Local/*.swift "$ROOT_DIR/Services/Browser/BrowserBridgeServer.swift" \
    "$ROOT_DIR/Tests/BrowserBridgeHarness.swift" -o "$ROOT_DIR/build/stage5/bridge-harness"
