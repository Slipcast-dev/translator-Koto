**Русский** | [English](BUILDING.en.md)

# Сборка и проверка

Нужны Apple Silicon, Xcode с macOS SDK, поддерживающим проект, Swift 6 и Python 3. Deployment target 26.0; компилятор Swift 6.2+ (Xcode 26+), режим языка Swift 6. Чистая сборка и harness на macOS 26 пройдены; полная интерактивная приёмка остаётся отдельной проверкой.

```sh
git clone --recurse-submodules https://github.com/Slipcast-dev/translator-Koto.git
cd translator-Koto
./script/build_local_runtime.sh
./script/build_native_host.sh
KOTO_CONFIGURATION=Release ./script/build_and_run.sh --build-only
python3 script/package_release.py
```

llama.cpp закреплён submodule и ThirdParty/llama-lock.json на `7894e8b92481a8bb8ffe94f73b656ffe0dd01e10`; verify_runtime_source.py сверяет SHA-256 дерева. Source-архивы GitHub не содержат submodule: при отсутствии дерева build_local_runtime.sh получает закреплённый upstream. cmake/ninja устанавливаются в build/tooling; runtime собирается статически с Metal. Веса не скачиваются. Бинарные runtime-ресурсы исключены из Git и восстанавливаются командами выше. DMG уже содержит runtime и не требует Xcode/Python.

```sh
python3 script/validate_repository.py
./script/test_manual_translation.sh
./script/test_capture.sh
./script/test_product_privacy.sh
./script/test_model_installation.sh
./script/test_quality_behaviors.sh
./script/test_bridge_protocol.sh
python3 script/test_bridge_integration.py
./script/test_apple_translation.sh
```

Реальный Apple smoke и transport-интеграция требуют готовых EN/RU ресурсов. Отсутствие ресурсов — отдельное состояние среды, не повод объявлять тест прошедшим. Qwen-тесты требуют установленную пользователем модель и не загружают её автоматически.

App/Features — UI и координация; Core — контракты, приватность и протокол; Services — движки/AX/OCR/bridge; NativeHost/NativeTools — собственные host/launcher; BrowserExtension — MV3; Resources/LocalModels — только каталог/лицензии; Tests/script — проверки/сборка. Локальные продукты и архив прежних отчётов исключены в build/.

Preview использует ad hoc. Developer ID/notarization — отдельный процесс. Не отключайте системные защиты ради проверки; ключи и исходный текст не должны попадать в журналы.

## Проверка локализации macOS

После Release-сборки выполните `python3 script/test_localization.py` и `./script/test_localization_dynamics.sh`. Проверяются готовые ru/en ресурсы, 12 сочетаний языковых предпочтений и региона, plural, числа, RTL, язык инструкций пояснений и schema=1. Дополнительные Python-пакеты и модель не нужны. Подробности и ограничения: [динамическая локализация](LOCALIZATION-DYNAMICS.md).

## Проверка локализации Chrome

Выполните `node --experimental-vm-modules --test Tests/BrowserLocalizationTests.mjs`, затем `./script/test_bridge_protocol.sh`. npm-пакеты не нужны. Node.js требуется только для тестов. Границы логических и нативных проверок: [локализация Chrome](LOCALIZATION-CHROME.md).

CI: `python3 script/validate_localization.py` и `python3 -m unittest discover -s Tests -p LocalizationCatalogTests.py`. Локальный пакет: `python3 script/package_release.py --artifact-suffix localization-hfs`; после монтирования — `python3 script/verify_localized_package.py /path/to/mounted/Koto`.

Первый запрос без ручного прогрева: закройте Koto и выполните `python3 script/test_browser_cold_start.py --app build/DerivedData/Build/Products/Release/Koto.app --language en`. Проверка требует готовые системные EN/RU ресурсы, не скачивает модель и не использует облако.

## CI / static analysis

`bash script/test_swift_ci.sh` runs ten deterministic Swift harnesses. `swiftlint lint --strict --config .swiftlint.yml` checks correctness rules without formatting unrelated code. Install the pinned SwiftLint 0.65.1 with `bash script/install_swiftlint.sh` (archive SHA-256 is verified); run `build/tooling/swiftlint/swiftlint lint --strict --config .swiftlint.yml`. GitHub Actions builds the app on macOS 26 arm64 and runs the same harnesses and lint rules. Dependabot monitors GitHub Actions and the llama.cpp submodule weekly; submodule updates require review and regeneration of the source locks before merging. Dependency Review checks newly introduced dependencies on pull requests. Pinned CMake/Ninja build tools and the model catalog are outside these automatic dependency checks.

## Проверяемое происхождение артефактов / Artifact provenance

`.github/workflows/build-artifacts.yml` builds preview artifacts from source on macOS 26 for a tag or manual workflow run and generates GitHub/Sigstore attestations. Download the workflow artifact, then verify each file with `gh attestation verify PATH --repo Slipcast-dev/translator-Koto --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml`. These attestations bind bytes to a GitHub workflow/source revision; they do not provide Apple Developer ID or notarization. Existing locally built alpha.13 assets have not been retroactively attested. The workflow is merged and its first alpha.14 tag build completed successfully. See Docs/validation/release-14.json for the verified source revision and artifact hashes.

`CFBundleShortVersionString` is numeric (0.1.0); `KotoReleaseChannel` stores alpha for the UI. Do not set `SWIFT_VERSION` to a compiler minor version: 6.0 denotes the language mode. Runtime model loading now uses an unlinked verified snapshot via inherited stdin; reserve temporary disk space equal to the model size in addition to installed weights. No named model copy is retained.
