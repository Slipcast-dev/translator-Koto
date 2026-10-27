#!/bin/bash
# Фиксированные версия и upstream digest: результат CI не зависит от состояния Homebrew.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT_DIR/build/tooling/swiftlint"
mkdir -p "$DEST"
ARCHIVE="$(mktemp "$DEST/archive.XXXXXX")"
trap 'rm -f "$ARCHIVE"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 \
  https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip -o "$ARCHIVE"
python3 - "$ARCHIVE" <<'CHECK'
"""Не распаковываем архив, пока не сверены байты с закреплённым upstream SHA-256."""
import hashlib
from pathlib import Path
import sys
expected = 'c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0'
actual = hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit('SwiftLint archive SHA-256 mismatch')
CHECK
/usr/bin/ditto -x -k "$ARCHIVE" "$DEST"
test "$("$DEST/swiftlint" version)" = '0.65.1'
