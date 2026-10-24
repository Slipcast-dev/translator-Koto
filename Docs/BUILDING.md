# Сборка и проверка

Нужны Apple Silicon, Xcode с macOS SDK, поддерживающим проект, Swift 6 и Python 3. Deployment target 26.0; проверенная система macOS 27.0.1. Запуск на 26 — отдельная незавершённая проверка.

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
