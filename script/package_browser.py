#!/usr/bin/env python3
"""Создать ZIP расширения и checksum всех артефактов текущей CI-поставки."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    """ZIP сохраняет папку BrowserExtension; веса и локальные продукты не копируются."""
    source = ROOT / 'BrowserExtension'
    version = json.loads((source / 'manifest.json').read_text())['version']
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    with zipfile.ZipFile(dist / f'Koto-Chrome-{version}.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(ROOT))
    records = []
    for path in sorted(dist.iterdir()):
        if path.is_file() and path.name != 'SHA256SUMS.txt':
            with path.open('rb') as artifact:
                digest = hashlib.file_digest(artifact, 'sha256').hexdigest()
            records.append(f'{digest}  {path.name}\n')
    (dist / 'SHA256SUMS.txt').write_text(''.join(records))


if __name__ == '__main__':
    main()
