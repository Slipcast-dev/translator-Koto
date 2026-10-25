# Локализация / Localization

25 октября / 25 October 2026. Локальная сборка / Local build.

Koto и Chrome имеют независимые интерфейсы ru/en с английским резервным языком.
Языковая пара, исходный текст и технические идентификаторы сохраняются.
Числа используют регион; грамматика — язык интерфейса. Есть поддержка RTL-текста.

Koto and Chrome use independent ru/en interfaces with English fallback.
The translation pair, original text and technical identifiers are preserved.
Numbers follow the region; grammar follows the interface language. RTL text is supported.

Проверены каталоги, fallback, plural, числа, schema=1, приватность и мост.
В Chrome ru/en выполнены переводы страницы и выделения, отмена и удаление.
Первые запросы к свежим процессам Koto прошли без ручного прогрева:
6/6 на текущей версии и 3/3 на исходной, через настоящий native host.
Первый page-запрос также проверен в нативном Chrome на обоих языках.

Catalogs, fallback, plurals, numbers, schema=1, privacy and the bridge were checked.
Page/selection translation, cancellation and removal ran in ru/en Chrome.
First requests to fresh Koto processes passed without a manual warm-up:
6/6 on the current version and 3/3 on the baseline, through the real native host.
The first page request was also checked in native Chrome in both languages.

Начальное состояние Working само по себе не означает зависание.
Ранее отмеченное ожидание не воспроизвелось как дефект; исправление не заявляется.
Системные службы Apple и их кэши при проверках не перезапускались.

The initial Working state alone does not establish a hang.
The previously observed wait did not reproduce as a defect; no hang fix is claimed.
Apple system services and their caches were not restarted during these checks.

Среда / Environment: arm64, macOS 27.2, Xcode 27.1, Chrome 155.0.8059.86.
macOS 26 не запускалась / macOS 26 runtime was not tested.
Qwen отсутствует: проверены инструкции, не генерация и не качество ответа.
Qwen is absent: instructions were checked; generation and response quality were not.
Независимая языковая экспертиза не проводилась / No independent linguistic review.
