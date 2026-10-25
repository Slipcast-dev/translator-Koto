#!/usr/bin/env python3
"""Проверить ru/en, plural и независимые регионы на ресурсах сборки Koto."""
from __future__ import annotations

import argparse
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def read_table(path: Path) -> dict[str, Any]:
    """Читать скомпилированные strings/stringsdict штатным plutil."""
    converted = subprocess.run(
        ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(path)],
        check=True, capture_output=True, text=True,
    )
    return json.loads(converted.stdout)


def normalize_spaces(value: str) -> str:
    """Разрешить эквивалентные разделители групп разных версий ICU."""
    return value.replace("\u00a0", " ").replace("\u202f", " ")


def verify(app: Path) -> dict[str, Any]:
    """Сверить ресурсы и запустить production lookup в отдельных процессах."""
    with (app / "Contents/Info.plist").open("rb") as source:
        metadata = plistlib.load(source)
    if metadata.get("CFBundleDevelopmentRegion") != "en":
        raise RuntimeError("Development region must be en")
    service_key = metadata["NSServices"][0]["NSMenuItem"]["default"]
    if service_key != "Translate in Koto":
        raise RuntimeError("Services fallback key changed")
    resources = app / "Contents/Resources"
    checked_values = 0
    plural_variants = 0
    tables: list[str] = []
    for table in ("Localizable", "ServicesMenu"):
        catalog = json.loads(
            (ROOT / "Resources" / f"{table}.xcstrings").read_text()
        )
        for language in ("en", "ru"):
            directory = resources / f"{language}.lproj"
            flat_path = directory / f"{table}.strings"
            flat = read_table(flat_path)
            tables.append(str(flat_path.relative_to(app)))
            plural_path = directory / f"{table}.stringsdict"
            plurals = read_table(plural_path) if plural_path.exists() else {}
            if plural_path.exists():
                tables.append(str(plural_path.relative_to(app)))
            for key, entry in catalog["strings"].items():
                translation = entry["localizations"][language]
                if "stringUnit" in translation:
                    unit = translation["stringUnit"]
                    if unit["state"] != "translated" or not unit["value"]:
                        raise RuntimeError(f"Incomplete translation: {key}")
                    if flat.get(key) != unit["value"]:
                        raise RuntimeError(f"Stale compiled key: {key}")
                    expected = re.findall(r"%(?:lld|@)", key)
                    if re.findall(r"%(?:lld|@)", unit["value"]) != expected:
                        raise RuntimeError(f"Placeholder mismatch: {key}")
                    checked_values += 1
                else:
                    # Проверяем скомпилированную stringsdict.
                    forms = translation["variations"]["plural"]
                    rule = plurals[key]
                    variable = re.search(
                        r"%#@([^@]+)@", rule["NSStringLocalizedFormatKey"]
                    )
                    if variable is None:
                        raise RuntimeError(f"Plural variable missing: {key}")
                    compiled = rule[variable[1]]
                    if compiled["NSStringFormatValueTypeKey"] != "lld":
                        raise RuntimeError(
                            f"Plural argument type changed: {key}"
                        )
                    if "other" not in forms:
                        raise RuntimeError(f"Plural other missing: {key}")
                    for form, definition in forms.items():
                        unit = definition["stringUnit"]
                        if unit["state"] != "translated" or not unit["value"]:
                            raise RuntimeError(f"Incomplete plural: {key}")
                        if compiled[form] != unit["value"]:
                            raise RuntimeError(f"Stale compiled plural: {key}")
                        tokens = re.findall(r"%(?:lld|@)", unit["value"])
                        if tokens != ["%lld"]:
                            raise RuntimeError(
                                f"Plural placeholder changed: {key}"
                            )
                        checked_values += 1
                        plural_variants += 1

    work = ROOT / "build/localization"
    work.mkdir(parents=True, exist_ok=True)
    # Копируются только .lproj, без весов, runtime и личных данных.
    with tempfile.TemporaryDirectory(prefix="probe-", dir=work) as temporary:
        contents = Path(temporary) / "LocalizationProbe.app/Contents"
        binary = contents / "MacOS/LocalizationProbe"
        binary.parent.mkdir(parents=True)
        (contents / "Resources").mkdir()
        for directory in resources.glob("*.lproj"):
            shutil.copytree(directory, contents / "Resources" / directory.name)
        with (contents / "Info.plist").open("wb") as destination:
            plistlib.dump({
                "CFBundleExecutable": "LocalizationProbe",
                "CFBundleIdentifier": "dev.slipcast.koto.localization-probe",
                "CFBundlePackageType": "APPL",
                "CFBundleDevelopmentRegion": "en",
            }, destination)
        subprocess.run([
            "/usr/bin/xcrun", "swiftc", "-parse-as-library",
            "-swift-version", "6", "-default-isolation", "MainActor",
            "-target", "arm64-apple-macosx26.0",
            *map(str, sorted((ROOT / "Core/Translation").glob("*.swift"))),
            str(ROOT / "Core/Migration/SettingsMigration.swift"),
            str(ROOT / "Tests/LocalizationProbe.swift"),
            "-o", str(binary),
        ], check=True)
        languages = [
            (["ru"], "ru"), (["en"], "en"),
            (["ru-RU"], "ru"), (["en-GB"], "en"), (["en-US"], "en"),
            (["fr-FR"], "en"), (["fr-FR", "ru-RU"], "ru"),
            (["en", "ru"], "en"),
        ]
        cases = [(preferences, language, "en_US")
                 for preferences, language in languages]
        cases += [
            (["en"], "en", "de_DE"), (["ru"], "ru", "ru_RU"),
            (["en"], "en", "ru_RU"), (["ru"], "ru", "de_DE"),
        ]
        expected = {
            "ru": {
                "about": "О Koto", "german_name": "немецкий",
                "empty_error": "Введите текст для перевода.",
                "same_language":
                    "Выберите разные языки источника и перевода.",
                "service": "Перевести в Koto",
                "cloud_denied": (
                    "Отправка этого источника в облако запрещена. "
                    "Разрешите её отдельно в настройках приватности."
                ),
            },
            "en": {
                "about": "About Koto", "german_name": "German",
                "empty_error": "Enter text to translate.",
                "same_language":
                    "Choose different source and target languages.",
                "service": "Translate in Koto",
                "cloud_denied": (
                    "Cloud sending is disabled for this source. "
                    "Enable it separately in privacy settings."
                ),
            },
        }
        counter = {
            "en_US": "42 / 20,000", "de_DE": "42 / 20.000",
            "ru_RU": "42 / 20 000",
        }
        numbers = {
            "en_US": "1,234,567", "de_DE": "1.234.567",
            "ru_RU": "1 234 567",
        }
        captured_ru = [
            "Захвачено 0 символов.", "Захвачен 1 символ.",
            "Захвачено 2 символа.", "Захвачено 5 символов.",
            "Захвачен 21 символ.", "Захвачено 22 символа.",
        ]
        memory_ru = ["0 фраз", "1 фраза", "2 фразы", "5 фраз",
                     "21 фраза", "22 фразы"]
        results: list[dict[str, Any]] = []
        for preferences, language, region in cases:
            # Аргументы действуют только для текущего тестового процесса.
            argument = "(" + ", ".join(f'"{tag}"' for tag in preferences) + ")"
            completed = subprocess.run([
                str(binary), "-AppleLanguages", argument,
                "-AppleLocale", region,
            ], check=True, capture_output=True, text=True)
            actual = json.loads(completed.stdout)
            if actual["preferred"][0] != language:
                raise RuntimeError(f"Unexpected UI language: {actual}")
            if not {"en", "ru"}.issubset(actual["available"]):
                raise RuntimeError("Missing bundle localization")
            for key, value in expected[language].items():
                if actual[key] != value:
                    raise RuntimeError(
                        f"{preferences}/{region}: {key}: {actual[key]!r}"
                    )
            if normalize_spaces(actual["counter"]) != counter[region]:
                raise RuntimeError(f"Counter ignores region: {actual}")
            if normalize_spaces(actual["number"]) != numbers[region]:
                raise RuntimeError(f"Number ignores region: {actual}")
            decimal = "2.5" if region == "en_US" else "2,5"
            if decimal not in actual["bytes"]:
                raise RuntimeError(f"Byte decimal ignores region: {actual}")
            for index, count in enumerate([0, 1, 2, 5, 21, 22]):
                prefix = captured_ru[index] if language == "ru" else (
                    f"Captured {count} character"
                    + ("." if count == 1 else "s.")
                )
                memory = memory_ru[index] if language == "ru" else (
                    f"{count} phrase" + ("" if count == 1 else "s")
                )
                if not actual["captured"][index].startswith(prefix):
                    raise RuntimeError(f"Wrong capture plural: {actual}")
                if memory not in actual["clear_memory"][index]:
                    raise RuntimeError(f"Wrong memory plural: {actual}")
            if actual["saved_settings"] != {
                "schema": 1, "appearance": "dark",
                "source": "ar", "target": "en"
            }:
                raise RuntimeError("Locale altered persisted language codes")
            if actual["missing_key"] != "Fallback available":
                raise RuntimeError("Missing key fallback failed")
            results.append({
                "preferences": preferences, "language": language,
                "region": region, "status": "passed", "actual": actual,
            })
    return {
        "status": "passed", "catalog_values_checked": checked_values,
        "plural_variants_checked": plural_variants,
        "cases": results, "compiled_tables": tables,
        "scope": (
            "Compiled resources, production rules and region/UI independence"
        ),
    }


def main() -> None:
    """Требовать готовую сборку и сохранить ограниченный отчёт проверок."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--app", type=Path,
        default=ROOT / "build/DerivedData/Build/Products/Release/Koto.app",
    )
    parser.add_argument(
        "--report", type=Path,
        default=ROOT / "build/localization/results.json",
    )
    arguments = parser.parse_args()
    result = verify(arguments.app.resolve())
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "status": result["status"],
        "language_region_cases": len(result["cases"]),
        "catalog_values": result["catalog_values_checked"],
        "plural_variants": result["plural_variants_checked"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
