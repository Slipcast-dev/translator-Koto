#!/bin/bash
# Koto должен работать. --expect-free проверяет отключённые hotkeys, без флага ожидается конфликт.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/stage3"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -target arm64-apple-macosx26.0 "$ROOT_DIR/Services/Hotkeys/GlobalHotkeyService.swift" \
    "$ROOT_DIR/Tests/HotkeyConflictProbe.swift" -o "$ROOT_DIR/build/stage3/hotkey-conflict-probe"
"$ROOT_DIR/build/stage3/hotkey-conflict-probe" "$@"
