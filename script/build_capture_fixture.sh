#!/bin/bash
# Создаёт локальный вспомогательный bundle только из нашего исходника, без сетевых зависимостей.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/build/stage3/KotoCaptureFixture.app"
mkdir -p "$FIXTURE_DIR/Contents/MacOS"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -target arm64-apple-macosx26.0 "$ROOT_DIR/Tests/CaptureFixture.swift" \
    -o "$FIXTURE_DIR/Contents/MacOS/KotoCaptureFixture"
/usr/bin/python3 -c 'import plistlib,sys; plistlib.dump({"CFBundleIdentifier":"dev.slipcast.koto.capture-fixture","CFBundleName":"KotoCaptureFixture","CFBundleExecutable":"KotoCaptureFixture","CFBundlePackageType":"APPL","LSMinimumSystemVersion":"26.0"},open(sys.argv[1],"wb"))' "$FIXTURE_DIR/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$FIXTURE_DIR"
echo "$FIXTURE_DIR"
