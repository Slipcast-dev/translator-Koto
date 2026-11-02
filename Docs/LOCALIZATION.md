**Русский** | English below

# Локализация Koto · Localization

## Русский

- **Языки:** интерфейс приложения и расширения Chrome — русский и английский; резервный язык — английский. Язык приложения выбирается средствами macOS и применяется после перезапуска, Chrome использует свой язык независимо.
- **Приложение:** `Resources/Localizable.xcstrings` и `Resources/ServicesMenu.xcstrings` (String Catalog, исходный язык en, обязательны переводы en и ru). Ключ — английский текст; параметры позиционные (`%@`, `%lld`); множественные числа заданы вариациями plural.
- **Chrome и Safari:** `BrowserExtension/_locales/{en,ru}/messages.json`; Safari использует те же файлы.
- **Числа, размеры, plural:** форматируются по региону, грамматика — по языку интерфейса (`Core/Translation/AppLocalization.swift`). Хранимые языковые коды и протокол не локализуются.
- **Добавление строки:** используйте `String(localized:)` с английским ключом, добавьте en и ru в каталог, затем выполните проверки.

```sh
python3 script/validate_localization.py
python3 -m unittest discover -s Tests -p LocalizationCatalogTests.py
node --experimental-vm-modules --test Tests/BrowserLocalizationTests.mjs
```

После Release-сборки: `python3 script/test_localization.py` и `./script/test_localization_dynamics.sh`.

## English

- **Languages:** the app and the Chrome extension ship Russian and English UIs with English fallback. The app language follows macOS and applies after a restart; Chrome uses its own language.
- **App:** `Resources/Localizable.xcstrings` and `Resources/ServicesMenu.xcstrings` (String Catalog, source language en, en and ru required). Keys are English text; arguments are positional (`%@`, `%lld`); plurals use plural variations.
- **Chrome and Safari:** `BrowserExtension/_locales/{en,ru}/messages.json`; Safari reuses the same files.
- **Numbers, sizes, plurals:** formatted by region, grammar by UI language (`Core/Translation/AppLocalization.swift`). Stored language codes and protocol values are never localized.
- **Adding a string:** use `String(localized:)` with the English key, add en and ru to the catalog, then run the checks above.
