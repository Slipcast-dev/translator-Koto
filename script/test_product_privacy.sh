#!/bin/bash
# Изолированный временный каталог и suite; настоящие данные/Keychain пользователя не изменяются.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/stage7"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macosx26.0 \
  "$ROOT_DIR"/Core/Translation/*.swift "$ROOT_DIR/Support/PrivateStorage.swift" \
  "$ROOT_DIR/Services/Product/TranslationStore.swift" "$ROOT_DIR/Tests/ProductPrivacyTests.swift" \
  -o "$ROOT_DIR/build/stage7/product-tests"
"$ROOT_DIR/build/stage7/product-tests"
