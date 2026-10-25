**Русский** | [English](README.en.md)

Локальная ru/en локализация от 25 октября: [приёмка и ограничения](Docs/LOCALIZATION-ACCEPTANCE.md). Текущий выпуск: **0.1.0-alpha.12**, Chrome **0.1.2**.

<p align="center"><img src="Docs/assets/banner.png" alt="Koto — Translate. Stay in flow. Native macOS translator by Slipcast-Dev" width="100%"></p>
<p align="center"><img alt="Alpha 12" src="https://img.shields.io/badge/release-0.1.0--alpha.12-efb366"> <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-333333"> <img alt="Apple Silicon" src="https://img.shields.io/badge/architecture-arm64-333333"> <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138"></p>

# Koto · Slipcast-Dev

Нативный переводчик для macOS: текст, выделение и область экрана, локальные движки и расширение Chrome. **Native macOS translation, built around your flow.**

**[Скачать DMG](https://github.com/Slipcast-dev/translator-Koto/releases/download/v0.1.0-alpha.12/Koto-0.1.0-alpha-12-arm64-preview.dmg)** · [Chrome 0.1.2 ZIP](https://github.com/Slipcast-dev/translator-Koto/releases/download/v0.1.0-alpha.12/Koto-Chrome-0.1.2.zip) · [Релизы](https://github.com/Slipcast-dev/translator-Koto/releases) · [Установка](Docs/INSTALLATION.md) · [Сборка](Docs/BUILDING.md) · [Статус](Docs/STATUS.md)

> Alpha preview для Apple Silicon. Подпись ad hoc, без Apple Developer ID/notarization: macOS может блокировать запуск. Проверки выпуска выполнялись на M1 / macOS 27.2; macOS 26 ещё не проверена.

## Возможности

| Возможность | Реализация |
| --- | --- |
| Ручной перевод | Apple Translation на устройстве; опциональная Qwen |
| Выделение | Accessibility, `⌃⌥⌘T` |
| OCR области | Vision на Mac, `⌃⌥⌘R` |
| Live | Живой перевод, `⌃⌥⌘L`; длительные испытания впереди |
| Chrome | Перевод выделения и видимых фрагментов через собственное расширение |
| Инструменты | Точные фразы, добровольная память, озвучивание и локальные пояснения |
| Облако | Google/Yandex адаптеры с ключом в Keychain; реальные аккаунты не аттестованы |

## Без встроенной модели

**В Git, приложении и DMG нет весов моделей.** Для Qwen нажмите **«Установить модель»** в настройках. Выбрана **Qwen3 4B Instruct 2507 · Q4_K_M**: около **2,50 GB**, Apache 2.0, минимум 8 GiB RAM. Загрузка проверяется по размеру и SHA-256; есть прогресс, отмена и удаление. Веса сохраняются только в пользовательском Application Support, вне проекта. [Выбор и качество модели →](Docs/MODELS.md)

Apple Translation использует системные языковые ресурсы. При их недоступности Koto предлагает явную подготовку. Build 11 также обрабатывает отказ session после успешной проверки ресурсов, сохраняя определённую языковую пару.

## Приватность

Выделение и OCR требуют разрешений macOS; снимки не сохраняются. Браузер передаёт текст по действию пользователя и не заменяет исходные DOM text nodes. Облачная отправка capture/browser/Live требует отдельных переключателей. Автоматического перехода в облако нет. Память по умолчанию выключена. [Подробности →](Docs/PRIVACY.md)

## Сборка

```sh
git clone --recurse-submodules https://github.com/Slipcast-dev/translator-Koto.git
cd translator-Koto
./script/build_local_runtime.sh
./script/build_native_host.sh
KOTO_CONFIGURATION=Release ./script/build_and_run.sh --build-only
python3 script/package_release.py
```

Нужны Xcode с подходящим macOS SDK, Swift 6, Apple Silicon и Python 3. Runtime собирается из закреплённого llama.cpp. Модель при сборке не скачивается. [Инструкция →](Docs/BUILDING.md)

## Проверки и ограничения

Для build 12 проверяются 546 локализованных значений в 12 сочетаниях языка/региона, 13 тестов Chrome и 9 тестов каталогов, а также основные регрессионные наборы. Нативные ru/en Chrome и первые запросы описаны в [приёмке](Docs/LOCALIZATION-ACCEPTANCE.md). [Описание выпуска](Docs/RELEASE-0.1.0-alpha.12.md).

Непостоянная внутренняя причина первоначального отказа Apple framework не установлена. Исправлена обработка отказа в Koto. Live endurance, sleep/wake, macOS 26 и часть внешних интеграций ещё требуют приёмки.

[Сообщить об ошибке](https://github.com/Slipcast-dev/translator-Koto/issues/new/choose) · [Участие](CONTRIBUTING.md) · [Безопасность](SECURITY.md) · [Изменения](CHANGELOG.md)

© 2026 **Slipcast-Dev**. Условия лицензирования собственного кода отдельно не указаны; файл LICENSE для него не добавлен. Сторонние компоненты сохраняют свои лицензии: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Иконка и баннер — AI-assisted artwork выбранной автором концепции.
