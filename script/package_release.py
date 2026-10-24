#!/usr/bin/env python3
"""Собрать проверяемый локальный alpha DMG. Trust/Gatekeeper не изменяются."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(args: list[str]) -> None:
    """Аргументы передаются напрямую, без shell и интерполяции пользовательских строк."""
    subprocess.run(args, check=True)


def sha256(path: Path) -> str:
    """Большая GGUF/DMG читается блоками, не целиком в память."""
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def validate_model_free_app(app: Path) -> None:
    """Отказ вместо тихого исключения: в пакете разрешены только метаданные модели."""
    forbidden = {".gguf", ".safetensors", ".onnx", ".pt", ".pth", ".partial"}
    if any(path.is_file() and path.suffix.lower() in forbidden for path in app.rglob("*")):
        raise RuntimeError("Model weights found in app bundle; rebuild without weights")
    catalog = app / "Contents/Resources/LocalModels"
    allowed = {"manifest.json", "MODEL-LICENSE.txt", "MODEL-NOTICE.txt"}
    if catalog.exists():
        for path in catalog.rglob("*"):
            if path.is_file() and (path.parent != catalog or path.name not in allowed or path.stat().st_size > 100_000):
                raise RuntimeError("Only small model catalog and license files may be bundled")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", default="-", help="SHA1 собственной Keychain identity; '-' = явно ad hoc preview")
    parser.add_argument("--app", type=Path, help="Готовый model-free app для упаковки")
    args = parser.parse_args()
    source = args.app or ROOT / "build/DerivedData/Build/Products/Release/Koto.app"
    if not source.is_dir():
        raise RuntimeError("Build Release first")
    with (source / "Contents/Info.plist").open("rb") as metadata_file:
        metadata = plistlib.load(metadata_file)
    version = metadata["CFBundleShortVersionString"]
    build = metadata["CFBundleVersion"]
    validate_model_free_app(source)
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    stage = ROOT / ("build/package-stage-" + version + "-" + str(build))
    if stage.is_symlink():
        raise RuntimeError("Unsafe staging directory")
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir()
    app = stage / "Koto.app"
    # ditto сохраняет bundle attributes и ресурсные forks, не обращаясь к исходному DMG.
    run(["/usr/bin/ditto", str(source), str(app)])
    resources = app / "Contents/Resources"
    runtime = resources / "LocalRuntime"
    for binary in [runtime / "llama-server", runtime / "koto-runtime-launcher", resources / "BrowserBridge/koto-native-host"]:
        run(["/usr/bin/codesign", "--force", "--sign", args.identity, "--options", "runtime", "--timestamp=none", str(binary)])
    # Supervisor проверяет bytes подписи nested tools. Обновление hash делается ДО подписи bundle.
    manifest_path = runtime / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["runtimeSHA256"] = sha256(runtime / "llama-server")
    manifest["launcherSHA256"] = sha256(runtime / "koto-runtime-launcher")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    run(["/usr/bin/codesign", "--force", "--sign", args.identity, "--options", "runtime", "--timestamp=none", str(app)])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
    os.symlink("/Applications", stage / "Applications")
    shutil.copytree(ROOT / "BrowserExtension", stage / "BrowserExtension")
    # Инструкции и уведомления едут рядом с приложением, чтобы их можно было прочитать до установки.
    shutil.copy2(ROOT / "Docs/INSTALLATION.md", stage / "INSTALLATION.md")
    shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.md", stage / "THIRD_PARTY_NOTICES.md")
    signing = "self-signed Slipcast-Dev" if args.identity != "-" else "AD HOC PREVIEW — без сертификата разработчика"
    (stage / "README.txt").write_text(
        "Koto · Slipcast-Dev · macOS 26+ · Apple Silicon · 8 ГБ RAM\n\n"
        + signing + "\nNot notarized. Собственная подпись не является Apple Developer ID.\n\n"
        "Перенесите Koto.app в Applications. Системные разрешения предоставляются этому приложению в настройках macOS.\n"
        "Apple Translation работает локально. Для Qwen откройте настройки и нажмите Установить модель (около 2,50 GB).\n"
        "Веса не входят в приложение или DMG; Google/Yandex требуют вашего API-ключа в Keychain.\n"
        "Расширение Chrome: developer mode → Load unpacked → BrowserExtension; host регистрируется кнопкой в Koto.\n"
        "Hotkeys: Control+Option+Command+T — выделение, +R — OCR, +L — Live.\n"
        "Системные подтверждения и Gatekeeper не отключаются скриптами Koto.\n", encoding="utf-8")
    name = f"Koto-{version}-{build}-arm64" + ("-self-signed" if args.identity != "-" else "-preview")
    dmg = dist / (name + ".dmg")
    run(["/usr/bin/hdiutil", "create", "-ov", "-format", "UDZO", "-volname", "Koto", "-srcfolder", str(stage), str(dmg)])
    run(["/usr/bin/hdiutil", "verify", str(dmg)])
    report = {"file": dmg.name, "sha256": sha256(dmg), "bytes": dmg.stat().st_size,
              "signing": signing, "notarized": False, "model_bundled": False, "optional_model_catalog": json.loads((resources / "LocalModels/manifest.json").read_text())}
    (dist / (name + ".json")).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
