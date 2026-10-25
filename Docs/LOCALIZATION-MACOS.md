# Инфраструктура локализации macOS — этап 3

Актуальный прогресс: [этап 4 — интерфейс Koto](LOCALIZATION-APP.md). Этот документ сохраняет снимок своего этапа.

Дата: 24 октября 2026 года. Статус: завершён в границах инфраструктуры и контрольных строк.

Основание: [требования](LOCALIZATION.md), [исходный реестр этапа 2](LOCALIZATION-INVENTORY.md). Полный перевод интерфейса выполняется на этапе 4. Расширение Chrome на этом этапе не изменялось.

## Архитектура и изменения

Koto использует штатный механизм локализации SwiftUI/Foundation. Отдельного переключателя языка, собственного словаря переводов или изменения UserDefaults не добавлено. Язык выбирается macOS из доступных en/ru; неподдерживаемые предпочтения получают английский резервный вариант. Изменение языка применяется при новом запуске процесса.

| Файл | Назначение |
| --- | --- |
| [Localizable.xcstrings](../Resources/Localizable.xcstrings) | sourceLanguage=en; переводы en/ru для About Koto и ошибки пустого ввода |
| [ServicesMenu.xcstrings](../Resources/ServicesMenu.xcstrings) | sourceLanguage=en; команда Services «Translate in Koto» / «Перевести в Koto» |
| [project.pbxproj](../Koto.xcodeproj/project.pbxproj) | Каталоги добавлены в Resources build phase и дерево проекта; developmentRegion=en, knownRegions=en/ru/Base |
| [Info.plist](../Config/Info.plist) | CFBundleDevelopmentRegion=en; английский NSMenuItem/default как ключ и резервный текст команды Services |
| [KotoApp.swift](../App/KotoApp.swift) | Заголовок окна сведений получает перевод по ключу About Koto |
| [KotoCommands.swift](../App/KotoCommands.swift) | Команда открытия окна использует тот же ключ |
| [TranslationModels.swift](../Core/Translation/TranslationModels.swift) | Production TranslationFailure.emptyText использует Foundation String(localized:) |
| [LocalizationProbe.swift](../Tests/LocalizationProbe.swift) | Консольная проверка Bundle.main, lookup и реальной production-ошибки |
| [test_localization.py](../script/test_localization.py) | Восемь языковых запусков на скомпилированных ресурсах готовой сборки |

В каталоге Localizable два ключа, в ServicesMenu один. Три перевода охватывают четыре исходных вхождения: окно, команду меню, ошибку и Services.

Имена Koto и Slipcast-Dev остаются брендами, поэтому отдельная таблица InfoPlist с одинаковыми переводами названия не добавлялась. Пользовательский текст NSServices локализуется через ServicesMenu, а не вложенные значения InfoPlist.strings.

Каталоги на этом этапе содержат ручные записи с комментариями для переводчика. Настройка LOCALIZATION_PREFERS_STRING_CATALOGS=YES уже существовала. Полный сбор строк SwiftUI и перенос оставшихся обычных String относятся к этапу 4; частичное покрытие не означает готовность английского интерфейса целиком.

## Правила дальнейшего переноса

- В SwiftUI использовать локализуемые литералы английского исходного языка: Window, Text, Button и другие подходящие инициализаторы.
- В сервисах, AppKit, вычисляемых подписях и LocalizedError использовать String(localized:) с контекстным комментарием. Это позволяет получать обычный String без зависимости от SwiftUI environment.
- Для строки, где ключ отличается от текста, использовать штатный defaultValue. Для динамических сообщений локализовать полный шаблон, сохраняя типы параметров.
- Ключ команды Services обязан точно совпадать с NSServices/NSMenuItem/default. NSMessage, имя host и маршруты регистрации не локализуются.
- Не использовать Locale.current как замену языка UI без проверки: язык ресурсов и регион форматирования решают разные задачи.
- Языковая пара, язык пояснений и политика облака сохраняют контракты этапа 1. Перенос названий языков и изменение промптов ещё не выполнялись.

Основание выбора штатных API: [подготовка текста к переводу](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation), [выбор доступных локалей Bundle](https://developer.apple.com/documentation/foundation/bundle/preferredlocalizations). Для Services Apple описывает отдельную таблицу с ключом default из Info.plist: [Services Properties](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html).

## Проверка

Среда текущего этапа: Apple Silicon/arm64, macOS 27.2 (26B118), Xcode 27.1 (27A9275). Это отдельная текущая проверка и не изменение исторических результатов alpha.11 на других версиях macOS. Запуск на macOS 26 не проверен.

До изменений проверка имеющихся build products не обнаружила en/ru Localizable.strings. После изменений Release-сборка создала и включила четыре таблицы:

- en.lproj/Localizable.strings
- en.lproj/ServicesMenu.strings
- ru.lproj/Localizable.strings
- ru.lproj/ServicesMenu.strings

Команды из корня Koto:

```sh
KOTO_CONFIGURATION=Release ./script/build_and_run.sh --build-only
python3 script/test_localization.py
./script/test_manual_translation.sh
codesign --verify --deep --strict --verbose=2 build/DerivedData/Build/Products/Release/Koto.app
```

Зависимости: те же Xcode/Swift 6 и Python 3, что нужны для сборки проекта. Дополнительные Python-пакеты не требуются. test_localization.py требует готовую Release-сборку; для другой сборки можно передать --app. Временный консольный bundle создаётся в build/localization и удаляется после проверки. Языки передаются только аргументами процесса, системные настройки не меняются.

| Проверка | Результат |
| --- | --- |
| Release build | BUILD SUCCEEDED, exit 0 |
| ru, en | Верные окно/ошибка/Services в ресурсо-проверке |
| ru-RU, en-GB, en-US | Используются общие ru/en |
| fr-FR | Резервный en |
| fr-FR, ru-RU | ru по порядку предпочтений |
| en, ru | en по порядку предпочтений |
| Отсутствующий ключ с defaultValue | Явный резервный текст |
| Production LocalizedError | TranslationFailure.emptyText проверен на обоих языках |
| Ручной перевод | 21 существующий state-machine тест, passed |
| Подпись app | strict/deep codesign verify, exit 0 |
| Модель в пакете | 0 файлов весов перечисленных форматов |
| Форматирование diff | git diff --check, exit 0 |

Сохранённые [машиночитаемые результаты](localization/stage3-results.json) содержат восемь случаев, сведения о сборке, UI-наблюдения и SHA-256 изменённых production-файлов и ресурсов. Временный лог нового запуска проверки сохраняется в build/localization/results.json.

## Реальное окно и меню

Собранный Release Koto запускался отдельно с -AppleLanguages '(en)' и '(ru)'. Через accessibility-интерфейс наблюдались:

| Язык | Команда меню Koto | Заголовок окна сведений |
| --- | --- | --- |
| en | About Koto | About Koto |
| ru | О Koto | О Koto |

В обоих запусках в главном окне наблюдалась та же выбранная пара en → ru и тот же движок Apple Translation; пользовательский текст не вводился. После проверки тестовые процессы Koto завершены. Изменение сохранённых настроек не выполнялось.

Foundation-проверка Services подтверждает перевод таблицы, ключ Info.plist и наличие ресурсов. Вызов Services из другого приложения и обновление кэша системного меню не проверялись на этом этапе. Ошибка проверена через production enum в консольном bundle с копией реальных скомпилированных .lproj, без добавления тестовой команды в Koto.

## Ограничения и следующий этап

- Остальной интерфейс пока русский: это ожидаемая граница этапа 3. Основной контент окна сведений тоже переносится на этапе 4.
- Таблица Services проверена на уровне ресурсов; полный сценарий захвата выделения относится к дальнейшей приёмке.
- Xcode сообщил о несовпадении версии CoreSimulator, пропуске AppIntents metadata и signed native host при stripping. macOS-сборка завершилась успешно; конфигурация симуляторов не менялась.
- DMG не пересобирался и публикация не выполнялась; проверено наличие ресурсов в Release app. Итоговая упаковка — этап 8.
- Реестр этапа 2 остаётся исходным снимком до переноса. Его номера строк и SHA-256 описывают тот снимок, а не изменённые файлы этого этапа.

Следующий этап — полный перенос пользовательских строк приложения Koto в каталоги, включая сервисы, настройки, ошибки, подсказки и доступность.
