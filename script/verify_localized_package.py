#!/usr/bin/env python3
"""Проверить автономный состав смонтированного локализованного DMG."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    """Небольшие ресурсы сравниваются побайтно через SHA-256."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(directory: Path) -> dict[str, int | str]:
    """Проверять содержимое DMG, а не только промежуточный staging-каталог."""
    app = directory / "Koto.app"
    resources = app / "Contents/Resources"
    tables = list(resources.glob("*.lproj/*.strings"))
    tables += list(resources.glob("*.lproj/*.stringsdict"))
    if len(tables) != 6:
        raise ValueError("Missing localized application tables")
    if any(path.suffix.lower() in {
        ".gguf", ".safetensors", ".onnx", ".pt", ".pth", ".partial"
    } for path in directory.rglob("*") if path.is_file()):
        raise ValueError("Model weights found in package")
    if digest(resources / "LICENSE") != digest(ROOT / "LICENSE"):
        raise ValueError("Application license is missing or stale")
    browser_files = 0
    for source in (ROOT / "BrowserExtension").rglob("*"):
        if source.is_file():
            relative = source.relative_to(ROOT / "BrowserExtension")
            target = directory / "BrowserExtension" / relative
            if not target.is_file() or digest(source) != digest(target):
                raise ValueError(f"Stale extension file: {relative}")
            browser_files += 1
    links = 0
    for path in directory.rglob("*.md"):
        if "Koto.app" in path.parts:
            continue
        for target in re.findall(r"\]\(([^\s)]+)", path.read_text()):
            if "://" in target or target.startswith("#"):
                continue
            resolved = path.parent / target.split("#")[0]
            if not resolved.exists():
                raise ValueError(f"Broken package link: {path.name}: {target}")
            links += 1
    for language, warning in (
        ("ru", "не нотарифицировано"), ("en", "not notarized")
    ):
        text = (directory / f"README.{language}.txt").read_text()
        if warning not in text or "{signing}" in text:
            raise ValueError(f"Missing signing warning: {language}")
        for stem in (
            "INSTALLATION", "BUILDING", "MODELS", "PRIVACY", "STATUS"
        ):
            suffix = ".en.md" if language == "en" else ".md"
            document = directory / "Docs" / (stem + suffix)
            if not document.is_file():
                raise ValueError(f"Missing user documentation: {stem}")
    for name in ("LICENSE", "CODE_OF_CONDUCT.md", "THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.en.md"):
        if digest(directory / name) != digest(ROOT / name):
            raise ValueError("Third-party notices changed during packaging")
    return {"status": "passed", "localized_tables": len(tables),
            "extension_files": browser_files, "local_document_links": links,
            "model_weights": 0}


def main() -> None:
    """Принимать только явно указанный смонтированный каталог."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.directory), ensure_ascii=False))


if __name__ == "__main__":
    main()
