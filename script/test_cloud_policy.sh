#!/bin/bash
# Только собственная UUID Keychain запись и конфигурация; реальных API-запросов нет.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/cloud-tests"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macosx26.0 \
  "$ROOT_DIR"/Core/Translation/*.swift "$ROOT_DIR/Services/Cloud/CloudTranslationEngine.swift" \
  "$ROOT_DIR/Tests/CloudPolicyTests.swift" -o "$ROOT_DIR/build/cloud-tests/policy-tests"
"$ROOT_DIR/build/cloud-tests/policy-tests"
