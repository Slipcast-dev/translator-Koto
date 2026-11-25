#!/bin/bash
# Host и desktop используют одну схему и закреплённый публичный origin.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# KOTO_TEST_HOOKS=1 собирает отдельный host для проверок в build/test-host; он не входит в приложение.
if [[ "${KOTO_TEST_HOOKS:-}" == "1" ]]; then
    OUTPUT="$ROOT_DIR/build/test-host/koto-native-host"
    FLAGS=(-D KOTO_TEST_HOOKS)
else
    OUTPUT="$ROOT_DIR/Resources/BrowserBridge/koto-native-host"
    FLAGS=()
fi
mkdir -p "$(dirname "$OUTPUT")"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -O -target arm64-apple-macosx26.0 ${FLAGS[@]+"${FLAGS[@]}"} "$ROOT_DIR"/Core/Bridge/*.swift \
    "$ROOT_DIR/Support/PrivateStorage.swift" "$ROOT_DIR/NativeHost/HostMain.swift" \
    -o "$OUTPUT"
codesign --force --sign - "$OUTPUT"
