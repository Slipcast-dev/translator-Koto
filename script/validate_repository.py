#!/usr/bin/env python3
"""Публичная проверка исходников: без весов/секретов и с целыми локальными ссылками."""
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    """Проверяет только индекс Git; не читает пользовательские каталоги или submodule."""
    tracked = subprocess.check_output(
        ['git', 'ls-files', '-z'], cwd=ROOT
    ).decode().split('\0')
    files = [ROOT / name for name in tracked if name and (ROOT / name).is_file()]
    forbidden = {'.gguf', '.safetensors', '.onnx', '.pth', '.pt', '.dmg', '.p12', '.pfx', '.key'}
    # Это форматы реальных ключей, а не слова api-key/secret из безопасных тестовых примеров.
    secrets = re.compile(
        r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|'
        r'gh[pousr]_[A-Za-z0-9]{30,}|sk-proj-[A-Za-z0-9_-]{30,}'
    )
    for path in files:
        relative = path.relative_to(ROOT)
        if path.suffix.lower() in forbidden:
            raise RuntimeError(f'Forbidden weight/installer/secret format: {relative}')
        if path.stat().st_size >= 100_000_000:
            raise RuntimeError(f'File exceeds GitHub object policy: {relative}')
        if relative.parts[0] in {'build', 'dist'}:
            raise RuntimeError(f'Generated product tracked: {relative}')
        if path.suffix in {'.md', '.swift', '.py', '.js', '.json', '.yml', '.sh'}:
            text = path.read_text()
            if secrets.search(text):
                raise RuntimeError(f'Potential secret: {relative}')
            if ('/' + 'Users' + '/') in text:
                raise RuntimeError(f'Personal absolute path: {relative}')
            if path.suffix == '.md':
                for target in re.findall(r'\]\(([^\s)]+)', text):
                    if '://' in target or target.startswith('#'):
                        continue
                    destination = (path.parent / target.split('#')[0]).resolve()
                    if not destination.exists():
                        raise RuntimeError(f'Broken local link in {relative}: {target}')
    catalog = json.loads((ROOT / 'Resources/LocalModels/manifest.json').read_text())
    lock = json.loads((ROOT / 'ThirdParty/model-lock.json').read_text())
    if catalog != lock:
        raise RuntimeError('Model catalog and lock differ')
    if not (ROOT / 'Docs/assets/banner.png').is_file():
        raise RuntimeError('Repository banner missing')
    if any(path.name == '.gitattributes' and 'filter=lfs' in path.read_text() for path in files):
        raise RuntimeError('No LFS model storage is allowed')
    print(json.dumps({'status': 'passed', 'tracked_files': len(files),
                      'model_weights': 0, 'broken_local_links': 0}))


if __name__ == '__main__':
    main()
