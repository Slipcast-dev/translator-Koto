#!/usr/bin/env python3
"""Проверить закреплённое дерево llama.cpp даже в source archive без .git."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    """Сверяется каждый включённый файл; дополнительные файлы тоже отвергаются."""
    source = ROOT / "ThirdParty/llama.cpp"
    manifest = json.loads((ROOT / "ThirdParty/llama-source-files.json").read_text())
    lock = json.loads((ROOT / "ThirdParty/llama-lock.json").read_text())
    if manifest["commit"] != lock["commit"]:
        raise RuntimeError("Source lock differs")
    actual: dict[str, str] = {}
    for path in source.rglob("*"):
        relative = path.relative_to(source)
        # Finder создаёт .DS_Store при просмотре папки; это метаданные интерфейса, не исходники runtime.
        if path.name == ".DS_Store" or ".git" in relative.parts or path.suffix in {".key", ".p12", ".pfx", ".gguf", ".partial", ".env"}:
            continue
        if path.is_file():
            if path.is_symlink():
                raise RuntimeError("Unexpected source symlink")
            actual[str(relative)] = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != manifest["files"]:
        raise RuntimeError("Runtime source tree SHA-256 differs from reviewed archive")
    print(json.dumps({"status": "passed", "source_files": len(actual), "commit": manifest["commit"]}))


if __name__ == "__main__":
    main()
