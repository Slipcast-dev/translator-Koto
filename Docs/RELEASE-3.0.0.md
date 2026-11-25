# Koto 3.0.0

**Русский.** Выпуск для Apple Silicon, macOS 26+. Подпись ad hoc, без Apple Developer ID и notarization: macOS может блокировать запуск. Веса моделей в DMG не входят. Расширение Chrome — 0.1.6: после обновления Koto установите его из настроек ещё раз и перезагрузите в Chrome.

**Новое.** Прогресс и готовые части длинного перевода (Qwen и облако). Метка живого перевода с названием движка, паузой и кнопкой «Остановить». Настраиваемые горячие клавиши. Импорт и экспорт точных фраз в JSON и CSV. Перевод страницы при прокрутке в расширениях Chrome и Safari (по умолчанию выключен).

**Исправлено.** Непрочитанный файл фраз или памяти сохраняется копией перед перезаписью. После «Стоп» живой перевод не отправляет новые запросы. Смена текста в крупной области замечается. Знаки препинания после ссылки не приводят к отклонению перевода. После сбоя живой перевод повторяет попытку или встаёт на паузу.

**Безопасность и надёжность.** Лимит запросов из браузера; захват через ⌘C можно отключить; обновление, после которого новая версия не запустилась, откатывается (действует для обновлений с 3.0.0 и новее); выпуск публикуется только после тестов; запросы к локальной модели выполняются по очереди.

**Проверки.** Автотесты и сборка проходят. Новые элементы интерфейса и расширения внутри Chrome и Safari вживую не проверялись: [статус](STATUS.md).

Файлы выпуска собираются из исходников workflow GitHub и подтверждаются attestation:

```sh
gh attestation verify PATH --repo Slipcast-dev/translator-Koto \
  --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml \
  --source-ref refs/heads/main
```

**English.** Release for Apple Silicon, macOS 26+. Ad hoc signed, without Apple Developer ID or notarization: macOS may block launch. The DMG contains no model weights. The Chrome extension is 0.1.6: after updating Koto, install it from Settings again and reload it in Chrome.

**New.** Progress and finished parts of long translations (Qwen and cloud). A live-translation badge with the engine name, Pause and Stop. Configurable global shortcuts. Import and export of exact phrases as JSON and CSV. Page translation while scrolling in the Chrome and Safari extensions (off by default).

**Fixed.** An unreadable phrase or memory file is kept as a backup before it is overwritten. After Stop, live translation sends no new requests. Text changes in large regions are detected. Punctuation after a link no longer rejects a translation. After a failure, live translation retries or pauses.

**Security and reliability.** A rate limit for browser requests; the ⌘C capture fallback can be turned off; an update whose new version never starts is rolled back (applies to updates from 3.0.0 onwards); releases are published only after tests; local-model requests are queued.

**Verification.** Automated tests and the build pass. The new interface elements and the extensions inside Chrome and Safari have not been tested live: [status](STATUS.en.md).

Release files are built from source by a GitHub workflow and carry attestations; verify with the command above.
