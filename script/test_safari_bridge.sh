#!/bin/bash
# Клиент расширения Safari против настоящего сервера моста. Safari и песочница не используются.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT_DIR/script/test_bridge_protocol.sh" > /dev/null
mkdir -p "$ROOT_DIR/build/safari-tests"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation nonisolated -target arm64-apple-macosx26.0 \
    "$ROOT_DIR"/Core/Bridge/*.swift "$ROOT_DIR/SafariExtension/SafariBridgeClient.swift" \
    "$ROOT_DIR/Tests/SafariBridgeClientTests.swift" -o "$ROOT_DIR/build/safari-tests/client-tests"
"$ROOT_DIR/build/safari-tests/client-tests" "$ROOT_DIR/build/stage5/bridge-harness"
