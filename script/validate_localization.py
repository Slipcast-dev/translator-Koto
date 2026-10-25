#!/usr/bin/env python3
"""Проверить полноту каталогов и подстановок без Xcode, модели и сети."""
from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import re
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
# Формат Foundation: позиционный индекс необязателен; %% — буквальный процент.
FORMAT = re.compile(r"%(?:(\d+)\$)?((?:ll|l)?[diuoxXfFeEgG@])|%%")


def signature(value: str) -> dict[int, str]:
    """Сравнить тип каждого аргумента, разрешая перестановку переводчиком."""
    result: dict[int, str] = {}
    sequential = 0
    for match in FORMAT.finditer(value):
        if match.group(0) == "%%":
            continue
        sequential += 1
        index = int(match.group(1) or sequential)
        kind = match.group(2)
        if index in result and result[index] != kind:
            raise ValueError("Conflicting format argument types")
        result[index] = kind
    return result


def translated_values(entry: dict[str, Any], language: str) -> list[str]:
    """Отклонять неполные переводы и пропущенные обязательные plural-формы."""
    localization = entry["localizations"][language]
    if "stringUnit" in localization:
        units = [localization["stringUnit"]]
    else:
        forms = localization["variations"]["plural"]
        required = {"one", "other"} if language == "en" else {
            "one", "few", "many", "other"
        }
        if set(forms) != required:
            raise ValueError(f"Incomplete plural forms: {language}")
        units = [form["stringUnit"] for form in forms.values()]
    if any(unit["state"] != "translated" or not unit["value"].strip()
           for unit in units):
        raise ValueError(f"Empty or unfinished translation: {language}")
    return [unit["value"] for unit in units]


def validate(root: Path = ROOT) -> dict[str, Any]:
    """Сверять контракт ru/en и все статические ссылки Chrome на сообщения."""
    values = 0
    keys = 0
    for path in sorted((root / "Resources").glob("*.xcstrings")):
        catalog = json.loads(path.read_text())
        if catalog["sourceLanguage"] != "en":
            raise ValueError(f"Wrong source language: {path.name}")
        for key, entry in catalog["strings"].items():
            if set(entry["localizations"]) != {"en", "ru"}:
                raise ValueError(f"Missing or unexpected locale: {key}")
            expected = signature(key)
            for language in ("en", "ru"):
                for value in translated_values(entry, language):
                    if signature(value) != expected:
                        raise ValueError(f"Format arguments differ: {key}")
                    values += 1
            keys += 1
    if keys == 0:
        raise ValueError("No String Catalog entries found")
    extension = root / "BrowserExtension"
    catalogs = {
        lang: json.loads(
            (extension / "_locales" / lang / "messages.json").read_text()
        ) for lang in ("en", "ru")
    }
    if set(catalogs["en"]) != set(catalogs["ru"]):
        raise ValueError("Chrome locale keys differ")
    for key, english in catalogs["en"].items():
        for language in ("en", "ru"):
            message = catalogs[language][key]
            if not message["message"].strip():
                raise ValueError(f"Empty Chrome message: {key}")
            # Имена placeholder нечувствительны к регистру; $1 сохраняется.
            expected = english.get("placeholders", {})
            actual = message.get("placeholders", {})
            if actual != expected:
                raise ValueError(
                    f"Chrome placeholder definition differs: {key}"
                )
            used = Counter(re.findall(
                r"\$([A-Za-z_]\w*)\$", message["message"].lower()
            ))
            if used != Counter(re.findall(r"\$([A-Za-z_]\w*)\$",
                                          english["message"].lower())):
                raise ValueError(f"Chrome placeholder missing: {key}")
    manifest = json.loads((extension / "manifest.json").read_text())
    if manifest.get("default_locale") != "en":
        raise ValueError("Chrome fallback must be en")
    for language in ("en", "ru"):
        if catalogs[language]["ui_language"]["message"] != language:
            raise ValueError("Chrome catalog language marker differs")
    identity = json.loads((extension / "identity.json").read_text())
    if manifest["key"] != identity["key"]:
        raise ValueError("Extension identity changed")
    required = set(re.findall(
        r'data-i18n="([^"]+)"', (extension / "popup.html").read_text()
    ))
    required.update(re.findall(r"__MSG_(\w+)__", json.dumps(manifest)))
    for name in ("popup.js", "i18n.js"):
        required.update(re.findall(
            r'message\("([a-z_]+)"', (extension / name).read_text()
        ))
    # Префикс page_translated_ строится динамически; проверяем все формы явно.
    required.discard("page_translated_")
    required.update("page_translated_" + form for form in
                    ("one", "few", "many", "other"))
    required.update("error_" + code for code in re.findall(
        r'"([a-z_]+)"', (extension / "i18n.js").read_text().split(
            "const errorCodes = new Set([", 1
        )[1].split("]);", 1)[0]
    ))
    if required - catalogs["en"].keys():
        missing = required - catalogs["en"].keys()
        raise ValueError(f"Missing Chrome keys: {missing}")
    return {"status": "passed", "catalog_keys": keys,
            "translated_values": values, "Chrome_messages_per_locale":
            len(catalogs["en"]), "Chrome_referenced_keys": len(required)}


if __name__ == "__main__":
    print(json.dumps(validate(), ensure_ascii=False))
