#!/bin/bash
# Сравнение настоящих движков. Не загружает системные языки и не обращается к cloud.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/quality" "$ROOT_DIR/Docs/Quality"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macosx26.0 \
 "$ROOT_DIR"/Core/Translation/*.swift "$ROOT_DIR"/Services/Local/*.swift \
 "$ROOT_DIR/Services/Translation/AppleTranslationEngine.swift" "$ROOT_DIR/Tests/TranslationQualityProbe.swift" \
 -o "$ROOT_DIR/build/quality/translation-quality-probe"
"$ROOT_DIR/build/quality/translation-quality-probe" "$ROOT_DIR/Resources" "${1:-local}" \
 "$ROOT_DIR/Tests/QualityFixtures.json" "$ROOT_DIR/Docs/Quality/${2:-latest}.json" "${@:3}"
