#!/bin/bash
# Проверяем transport без GGUF, сети и пользовательских настроек.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/runtime-tests"
# Проверяем именно дерево процессов production launcher, а не предположение о ppid.
xcrun clang++ -std=c++20 -O2 -arch arm64 -mmacosx-version-min=26.0 "$ROOT_DIR/NativeTools/RuntimeLauncher.cpp" -o "$ROOT_DIR/build/runtime-tests/koto-runtime-launcher"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macosx26.0 \
    "$ROOT_DIR"/Core/Translation/*.swift "$ROOT_DIR"/Services/Local/*.swift \
    "$ROOT_DIR/Tests/RuntimeTransportTests.swift" -o "$ROOT_DIR/build/runtime-tests/transport-tests"
"$ROOT_DIR/build/runtime-tests/transport-tests" "$ROOT_DIR/Tests/RuntimeTransportServer.py" "$ROOT_DIR/build/runtime-tests/koto-runtime-launcher" "$(command -v python3)"
