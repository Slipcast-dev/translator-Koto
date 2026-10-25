# Koto 0.1.0-alpha.12 · Chrome 0.1.2

## Русский

Русский и английский интерфейсы Koto и расширения Chrome с независимым выбором языка. Региональное форматирование чисел и размеров, plural-формы, отображение RTL-текста. Пояснения запрашиваются на языке Koto, варианты перевода — на целевом языке, цитаты сохраняются в оригинале.

Каталоги и параметры подстановки проверяются в CI. Ошибки моста передаются стабильными кодами и переводятся в popup. Настройки schema=1, ID расширения, native-протокол и разрешения сохранены.

Установщик HFS+ содержит приложение, расширение, инструкции и уведомления о лицензиях на двух языках. Веса моделей отсутствуют. Расширение также поставляется отдельным ZIP; после распаковки загрузите папку BrowserExtension через chrome://extensions → режим разработчика → загрузить распакованное.

Подпись ad hoc preview, без Apple Developer ID и нотарификации: macOS может заблокировать запуск. Защиты системы не изменяются. Проверено на arm64/macOS 27.2; macOS 26 не запускалась. Фактическая генерация Qwen и независимая языковая экспертиза не проверялись.

## English

Russian and English interfaces for Koto and its Chrome extension, with independent language selection. Regional number and size formatting, plural forms and RTL text presentation. Explanations are requested in Koto's language, alternatives use the target language, and original quotes are preserved.

CI validates catalogs and substitutions. Stable bridge error codes are localized by the popup. Settings schema=1, extension identity, native protocol and permissions are preserved.

The HFS+ installer includes the app, extension, bilingual instructions and license notices. No model weights are bundled. The extension is also available as a separate ZIP; extract it and load BrowserExtension at chrome://extensions → Developer mode → Load unpacked.

Ad hoc preview signing, without Apple Developer ID or notarization: macOS may block launch. System protections are unchanged. Verified on arm64/macOS 27.2; macOS 26 runtime, actual Qwen generation and independent linguistic review remain unverified.

Assets: Koto-0.1.0-alpha-12-arm64-preview.dmg, Koto-Chrome-0.1.2.zip, SHA256SUMS.txt and the package JSON report.
