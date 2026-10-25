"""Регрессии валидатора: пропуск перевода должен ломать CI до сборки."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "script"))
from validate_localization import ROOT, validate


class CatalogTests(unittest.TestCase):
    """Изменять только копии каталогов, не рабочие переводы."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "Resources").mkdir()
        for path in (ROOT / "Resources").glob("*.xcstrings"):
            shutil.copy2(path, self.root / "Resources" / path.name)
        shutil.copytree(ROOT / "BrowserExtension",
                        self.root / "BrowserExtension")

    def change(self, name: str, mutate: Callable[[Any], None]) -> None:
        """Испортить один независимый контракт в изолированной копии."""
        path = self.root / name
        data = json.loads(path.read_text())
        mutate(data)
        path.write_text(json.dumps(data))
        with self.assertRaises((ValueError, KeyError)):
            validate(self.root)

    def test_current_catalogs(self) -> None:
        self.assertEqual(validate(self.root)["status"], "passed")

    def test_missing_locale(self) -> None:
        self.change("Resources/Localizable.xcstrings",
                    lambda data: data["strings"]["Translate"]
                    ["localizations"].pop("ru"))

    def test_empty_translation(self) -> None:
        self.change("Resources/Localizable.xcstrings",
                    lambda data: data["strings"]["Translate"]["localizations"]
                    ["ru"]["stringUnit"].update(value=" "))

    def test_argument_type(self) -> None:
        self.change("Resources/Localizable.xcstrings",
                    lambda data: data["strings"]["%@ / %@"]["localizations"]
                    ["ru"]["stringUnit"].update(value="%lld / %@"))

    def test_missing_plural(self) -> None:
        self.change("Resources/Localizable.xcstrings",
                    lambda data: data["strings"]["Clear memory (%lld)"]
                    ["localizations"]["ru"]["variations"]["plural"].pop("few"))

    def test_missing_chrome_message(self) -> None:
        self.change("BrowserExtension/_locales/en/messages.json",
                    lambda data: data.pop("cancel"))

    def test_chrome_substitution(self) -> None:
        self.change("BrowserExtension/_locales/ru/messages.json",
                    lambda data: data["page_translated_one"].update(
                        message="Пропущено число."))

    def test_chrome_identity(self) -> None:
        self.change("BrowserExtension/manifest.json",
                    lambda data: data.update(key="different-public-key"))

    def test_chrome_fallback(self) -> None:
        self.change("BrowserExtension/manifest.json",
                    lambda data: data.update(default_locale="ru"))


if __name__ == "__main__":
    unittest.main()
