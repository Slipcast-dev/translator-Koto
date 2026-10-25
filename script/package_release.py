#!/usr/bin/env python3
"""Собрать проверяемый локальный alpha DMG, сохраняя защиты macOS."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(args: list[str]) -> None:
    """Передавать аргументы напрямую, без shell-интерполяции путей."""
    subprocess.run(args, check=True)


def sha256(path: Path) -> str:
    """Читать большие файлы блоками, не загружая DMG целиком в память."""
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def validate_model_free_app(app: Path) -> None:
    """Отказывать при весах; в пакете разрешены лишь метаданные модели."""
    forbidden = {".gguf", ".safetensors", ".onnx", ".pt", ".pth", ".partial"}
    if any(path.is_file() and path.suffix.lower() in forbidden
           for path in app.rglob("*")):
        raise RuntimeError("Model weights found in app; rebuild without them")
    catalog = app / "Contents/Resources/LocalModels"
    allowed = {"manifest.json", "MODEL-LICENSE.txt", "MODEL-NOTICE.txt"}
    if catalog.exists():
        for path in catalog.rglob("*"):
            if path.is_file() and (
                path.parent != catalog or path.name not in allowed
                or path.stat().st_size > 100_000
            ):
                raise RuntimeError("Only small model metadata may be bundled")


def write_documentation(stage: Path, identity: str) -> None:
    """Сохранять ru/en и локальные ссылки без копирования всего репозитория."""
    directory = stage / "Docs"
    directory.mkdir()
    reports = (
        "LOCALIZATION-DYNAMICS.md", "LOCALIZATION-CHROME.md",
        "LOCALIZATION-ACCEPTANCE.md",
    )
    for stem in ("INSTALLATION", "BUILDING", "MODELS", "PRIVACY", "STATUS"):
        for suffix in (".md", ".en.md"):
            name = stem + suffix
            text = (ROOT / "Docs" / name).read_text()
            # Инженерные отчёты требуют исходников. Автономный пакет получает
            # двуязычный отчёт без ссылок на отсутствующие исходные файлы.
            for report in reports:
                text = text.replace("(" + report + ")", "(LOCALIZATION.md)")
            (directory / name).write_text(text)
    validation = directory / "validation"
    validation.mkdir()
    shutil.copy2(
        ROOT / "Docs/validation/results.json", validation / "results.json"
    )
    for name in ("THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.en.md"):
        shutil.copy2(ROOT / name, stage / name)
    # Текущие release notes и machine-readable проверки нужны и вне репозитория.
    for path in (ROOT / "Docs").glob("RELEASE-*.md"):
        shutil.copy2(path, directory / path.name)
    for path in (ROOT / "Docs/validation").glob("release-*.json"):
        shutil.copy2(path, validation / path.name)
    templates = ROOT / "Resources/Distribution"
    if identity == "-":
        labels = {
            "ru": (
                "ПРЕДВАРИТЕЛЬНАЯ СБОРКА: подпись ad hoc, "
                "без сертификата разработчика."
            ),
            "en": "PREVIEW: ad hoc signing, without a developer certificate.",
        }
    else:
        labels = {
            "ru": (
                "Собственная подпись Slipcast-Dev; "
                "сертификат не выдан Apple."
            ),
            "en": (
                "Self-signed by Slipcast-Dev; "
                "the certificate was not issued by Apple."
            ),
        }
    for language, signing in labels.items():
        name = "README." + language + ".txt"
        text = (templates / name).read_text().format(signing=signing)
        (stage / name).write_text(text)
    shutil.copy2(templates / "LOCALIZATION.md", directory / "LOCALIZATION.md")
    (stage / "README.txt").write_text(
        "Koto · Slipcast-Dev\n\n"
        "Русский: README.ru.txt и Docs/INSTALLATION.md\n"
        "English: README.en.txt and Docs/INSTALLATION.en.md\n"
    )


def main() -> None:
    """Упаковать готовый app, подписать вложенные инструменты и сверить DMG."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--identity", default="-",
        help="SHA1 собственной Keychain identity; '-' = ad hoc preview",
    )
    parser.add_argument(
        "--app", type=Path, help="Готовый model-free app для упаковки"
    )
    parser.add_argument(
        "--artifact-suffix", default="",
        help="Суффикс локального пакета, сохраняющий прежний выпуск",
    )
    args = parser.parse_args()
    if args.artifact_suffix and not re.fullmatch(
        r"[a-z0-9-]+", args.artifact_suffix
    ):
        parser.error("artifact-suffix must contain a-z, digits or hyphens")
    suffix = "-" + args.artifact_suffix if args.artifact_suffix else ""
    source = args.app or (
        ROOT / "build/DerivedData/Build/Products/Release/Koto.app"
    )
    if not source.is_dir():
        raise RuntimeError("Build Release first")
    with (source / "Contents/Info.plist").open("rb") as metadata_file:
        metadata = plistlib.load(metadata_file)
    version = metadata["CFBundleShortVersionString"]
    build = metadata["CFBundleVersion"]
    validate_model_free_app(source)
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    stage = ROOT / ("build/package-stage-" + version + "-" + str(build)
                    + suffix)
    if stage.is_symlink():
        raise RuntimeError("Unsafe staging directory")
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir()
    app = stage / "Koto.app"
    # ditto сохраняет атрибуты bundle, не изменяя исходную сборку.
    run(["/usr/bin/ditto", str(source), str(app)])
    resources = app / "Contents/Resources"
    runtime = resources / "LocalRuntime"
    binaries = [
        runtime / "llama-server", runtime / "koto-runtime-launcher",
        resources / "BrowserBridge/koto-native-host",
    ]
    for binary in binaries:
        run([
            "/usr/bin/codesign", "--force", "--sign", args.identity,
            "--options", "runtime", "--timestamp=none", str(binary),
        ])
    # Supervisor сверяет hash вложенных tools; обновляем его до подписи app.
    manifest_path = runtime / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["runtimeSHA256"] = sha256(runtime / "llama-server")
    manifest["launcherSHA256"] = sha256(runtime / "koto-runtime-launcher")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    run([
        "/usr/bin/codesign", "--force", "--sign", args.identity,
        "--options", "runtime", "--timestamp=none", str(app),
    ])
    run([
        "/usr/bin/codesign", "--verify", "--deep", "--strict",
        "--verbose=2", str(app),
    ])
    os.symlink("/Applications", stage / "Applications")
    shutil.copytree(ROOT / "BrowserExtension", stage / "BrowserExtension")
    write_documentation(stage, args.identity)
    signing = ("self-signed Slipcast-Dev" if args.identity != "-"
               else "AD HOC PREVIEW")
    kind = "-self-signed" if args.identity != "-" else "-preview"
    name = f"Koto-{version}-{build}-arm64" + kind + suffix
    dmg = dist / (name + ".dmg")
    # Явно задаём HFS+: чтение APFS mount зависало в среде QA.
    # Выбор файловой системы образа не изменяет диск или защиты пользователя.
    run([
        "/usr/bin/hdiutil", "create", "-ov", "-format", "UDZO", "-fs",
        "HFS+", "-volname", "Koto", "-srcfolder", str(stage), str(dmg),
    ])
    run(["/usr/bin/hdiutil", "verify", str(dmg)])
    report = {
        "file": dmg.name, "sha256": sha256(dmg), "bytes": dmg.stat().st_size,
        "signing": signing, "notarized": False, "model_bundled": False,
        "optional_model_catalog": json.loads(
            (resources / "LocalModels/manifest.json").read_text()
        ),
    }
    (dist / (name + ".json")).write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    )
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
