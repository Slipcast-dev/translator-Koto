**Русский** | [English](BUILDING.en.md)

# Сборка, проверка и выпуск

Нужны Apple Silicon, Xcode с macOS SDK, поддерживающим проект, Swift 6 и Python 3. Deployment target 26.0; компилятор Swift 6.2+ (Xcode 26+), режим языка Swift 6.

## Сборка

```sh
git clone --recurse-submodules https://github.com/Slipcast-dev/translator-Koto.git
cd translator-Koto
./script/build_local_runtime.sh
./script/build_native_host.sh
KOTO_CONFIGURATION=Release ./script/build_and_run.sh --build-only
python3 script/package_release.py
```

- **Runtime.** llama.cpp закреплён submodule и `ThirdParty/llama-lock.json` на `7894e8b92481a8bb8ffe94f73b656ffe0dd01e10`; `verify_runtime_source.py` сверяет SHA-256 дерева. Source-архивы GitHub не содержат submodule: при отсутствии дерева `build_local_runtime.sh` получает закреплённый upstream. cmake и ninja устанавливаются в `build/tooling`; runtime собирается статически с Metal. Веса не скачиваются. Бинарные runtime-ресурсы исключены из Git и восстанавливаются командами выше. DMG уже содержит runtime и не требует Xcode и Python.
- **Targets.** Приложение `Koto` и расширение Safari `Koto Safari` (папка `SafariExtension/`, встраивается в `Koto.app/Contents/PlugIns`; общие popup и локализация берутся из `BrowserExtension/`).
- **Версия.** `CFBundleShortVersionString` числовая (`MARKETING_VERSION`), канал alpha хранится в `KotoReleaseChannel`, номер сборки — `CURRENT_PROJECT_VERSION` в `Config/Product.xcconfig`. Не задавайте `SWIFT_VERSION` минорной версией компилятора: 6.0 означает режим языка.
- **Подпись.** Preview использует ad hoc; Developer ID и notarization — отдельный процесс. Не отключайте системные защиты ради проверки.
- **Модель.** Запуск идёт из анонимного проверенного снимка через унаследованный stdin; на APFS снимок — мгновенный клон copy-on-write без дополнительного места, иначе делается полная копия (нужно временное место размером с модель). Без запросов runtime выгружается через 10 минут.

## Структура

`App`, `Features` — интерфейс и координация; `Core` — контракты, приватность и протокол; `Services` — движки, Accessibility, OCR, мост, обновление; `NativeHost`, `NativeTools` — собственные host и launcher; `BrowserExtension` — MV3 для Chrome; `SafariExtension` — расширение Safari; `Resources/LocalModels` — только каталог и лицензии; `Tests`, `script` — проверки и сборка.

## Проверки

```sh
python3 script/validate_repository.py
python3 script/validate_localization.py
bash script/test_swift_ci.sh
python3 script/test_bridge_integration.py
build/tooling/swiftlint/swiftlint lint --strict --config .swiftlint.yml
```

- `test_swift_ci.sh` выполняет 13 детерминированных прогонов: 9 shell-наборов (ручной перевод, захват, приватность, установка модели, качество, протокол моста, транспорт runtime, динамика локализации, политика облака), прямые harness Live и миграции настроек, проверку обновления на настоящих DMG и клиент моста Safari, а также Python-проверку длинного пути сокета. Модель и разрешения экрана не нужны.
- SwiftLint 0.65.1 ставится командой `bash script/install_swiftlint.sh` (SHA-256 архива проверяется).
- Реальный Apple smoke (`./script/test_apple_translation.sh`) и интеграция моста требуют готовых системных ресурсов EN/RU. Их отсутствие — состояние среды, а не повод считать тест пройденным. Qwen-тесты требуют установленной пользователем модели.
- Локализация: после Release-сборки `python3 script/test_localization.py` и `./script/test_localization_dynamics.sh`; Chrome: `node --experimental-vm-modules --test Tests/BrowserLocalizationTests.mjs`; каталоги: `python3 -m unittest discover -s Tests -p LocalizationCatalogTests.py`. Подробнее: [LOCALIZATION.md](LOCALIZATION.md).
- Пакет: после `package_release.py` смонтируйте DMG и выполните `python3 script/verify_localized_package.py /path/to/mounted/Koto`.
- Первый запрос без прогрева: `python3 script/test_browser_cold_start.py --app build/DerivedData/Build/Products/Release/Koto.app --language en` (нужны системные ресурсы EN/RU; модель не скачивается, облако не используется).
- Для снимков интерфейса приложение принимает аргумент `--koto-open-settings`, который открывает окно настроек.

CI GitHub на macOS 26 собирает приложение без подписи, выполняет SwiftLint и `test_swift_ci.sh`; отдельно работают CodeQL и Dependency Review. Dependabot раз в неделю проверяет GitHub Actions и submodule llama.cpp; обновление submodule требует проверки runtime.

## Выпуск

Выпуск автоматический. В pull request увеличьте `CURRENT_PROJECT_VERSION` в `Config/Product.xcconfig` и добавьте `Docs/RELEASE-<версия>.md` (например `RELEASE-0.1.0-alpha.17.md`, двуязычные заметки, ссылки только абсолютные или на соседние документы). После слияния в `main` workflow `.github/workflows/build-artifacts.yml`:

1. собирает приложение из исходников на macOS 26;
2. упаковывает DMG, ZIP расширения Chrome и `SHA256SUMS.txt`;
3. подтверждает файлы attestation GitHub/Sigstore;
4. создаёт тег `v<версия>-alpha.<build>` и prerelease с заметками.

Если релиз этой версии уже есть, сборка пропускается; тот же workflow можно запустить вручную или тегом `v*`. Прежние релизы workflow не удаляет. Сайт [koto-website](https://github.com/Slipcast-dev/koto-website) сам подхватывает последний релиз и обновляет ссылки скачивания. Проверка файла: `gh attestation verify PATH --repo Slipcast-dev/translator-Koto --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml`. Attestation связывает файлы с исходной ревизией и workflow, но не заменяет Apple Developer ID и notarization.

Изменения в `main` вносятся pull request с включённым авто-слиянием после обязательных проверок.
