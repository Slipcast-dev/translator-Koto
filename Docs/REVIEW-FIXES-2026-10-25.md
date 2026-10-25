# Проверка пяти замечаний · 25 октября 2026

Все пять замечаний подтверждены по исходному коду и исправлены. Исправления подготовлены к выпуску alpha.13 после alpha.12.

## Архитектура исправлений

| Замечание | Изменение | Свежая проверка |
| --- | --- | --- |
| Runtime / подмена endpoint | TCP и поиск свободного порта удалены. llama-server слушает AF_UNIX в уникальном каталоге /tmp с режимом 0700. Перед каждым запросом на уже подключённом сокете проверяются UID и kernel peer PID: peer должен быть дочерним процессом живого launcher. HTTP 200 не устанавливает доверие. Health не содержит токен; перевод отправляется только после проверки peer на том же соединении. | RuntimeTransportTests: доверенные health/POST проходят; сервер того же UID с другим parent PID на том же повторно использованном пути получает 0 байтов для health и POST. |
| Privacy / конечная точка DNS | Host нормализуется перед сопоставлением домена и поддоменов. | ProductPrivacyTests: example.com, example.com., Sub.Example.COM. блокируются; notexample.com. разрешён. |
| OCR / Pause → Resume | Новый захват ожидает освобождения единственного OCR, поддерживая отмену. Результат отменённого producer отбрасывается. | CaptureTests: незавершённый OCR переживает cancel; Resume ждёт и затем получает новый кадр; отменённый waiter завершается. |
| Языки / смена движка | Каждая загрузка получает UUID поколения и сразу очищает старый каталог. Только последний запрос публикует список, ошибку и состояние загрузки. | ManualTranslationTests: старые success/error после нового запроса не меняют актуальный каталог или loading. |
| CI | macOS 26 arm64: сборка app без подписи и десять Swift harness через общий script/test_swift_ci.sh. | Эквивалентные build и harness выполнены локально. Удалённый GitHub Actions в этой сессии не запускался. |

## Запуск

```sh
bash script/test_swift_ci.sh
xcodebuild -project Koto.xcodeproj -scheme Koto -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/ReviewDerived \
  CODE_SIGNING_ALLOWED=NO build
python3 script/validate_repository.py
python3 script/validate_localization.py
python3 -m unittest discover -s Tests -p LocalizationCatalogTests.py
node --experimental-vm-modules --test Tests/BrowserLocalizationTests.mjs
```

Нужны arm64 Mac, macOS 26+, Xcode со Swift 6.2+ (флаг default-isolation), Python 3 и Node.js. Scheme содержит app target без XCTest target: проверки запускаются общим shell script, а не xcodebuild test. CI использует тот же script и завершается с ошибкой при первом неуспешном harness.

## Результат и границы

Проверено локально на macOS 27.2 / Xcode 27.1: Debug build — пройдено; все десять Swift harness — пройдено. Веса не скачивались, разрешения экрана не требовались; Vision распознавал синтетическое изображение. Полная генерация Qwen через новый транспорт, crash/quit с реальными весами, интерактивный Live и выполнение на macOS 26 — не проверено. Transport fixture использует настоящий production launcher, AF_UNIX и kernel credentials; заменяется только llama-server на одноразовый HTTP fixture.

Существующие release-результаты относятся к опубликованной alpha.12. CI workflow включён в alpha.13; фактический удалённый результат отслеживается в GitHub Actions. Приёмочная матрица использует статусы «пройдено / не пройдено / не проверено» и не переносит прохождение unit-контрактов на неиспытанные реальные сценарии.

После публикации alpha.13: [удалённый CI](https://github.com/Slipcast-dev/translator-Koto/actions/runs/40202546241) прошёл на macOS 26 arm64 — сборка, SwiftLint и все десять harness. Сбой чистого checkout устранён явной сборкой native host перед Xcode. Упоминания отсутствующего удалённого результата выше относятся к первоначальному локальному этапу проверки.
