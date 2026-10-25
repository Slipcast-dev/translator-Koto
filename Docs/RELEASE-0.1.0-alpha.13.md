# Koto 0.1.0-alpha.13 · Chrome 0.1.3

## Русский

Исправлены подмена локального runtime (AF_UNIX и проверка kernel peer identity до отправки данных), обход исключённого домена конечной точкой DNS, гонка OCR Pause/Resume и устаревший каталог при смене движка. Добавлены macOS CI-сборка, десять Swift harness, SwiftLint, Dependabot и Dependency Review для pull requests.

Добавлены правила сообщества. Условия распространения собственного кода указаны в корневом LICENSE; сторонние компоненты сохраняют свои лицензии. Документация, установщик и ZIP Chrome обновлены совместно. Chrome 0.1.3 сохраняет ID, permissions и native protocol; изменения браузерной приватности находятся в приложении.

Проверки выпуска: macOS 27.2 / Xcode 27.1; сборка Release, десять Swift harness, SwiftLint, Python/JS-регрессии и верификация пакета. Результат удалённого macOS 26 CI публикуется отдельно. Реальная генерация Qwen через новый транспорт и интерактивная длительная Live-сессия не проверены; веса не скачивались.

Подпись ad hoc preview, без Developer ID/notarization. Защиты macOS не изменяются. Веса моделей не включены в app, Git или DMG.

## English

Fixes runtime impersonation using AF_UNIX with kernel peer identity checks before data is sent, trailing-dot domain exclusion bypass, OCR Pause/Resume races, and stale language catalogs after engine changes. Adds macOS builds, ten Swift harnesses, SwiftLint, Dependabot, and pull-request Dependency Review.

Adds a community code of conduct. First-party distribution terms are provided in the root LICENSE; third-party licenses remain separate. The documentation, installer, and Chrome ZIP are updated together. Chrome 0.1.3 preserves extension identity, permissions, and native protocol; the browser privacy fix is in the app.

Release verification uses macOS 27.2 / Xcode 27.1. Remote macOS 26 CI is reported separately. Actual Qwen generation through the new transport and extended interactive Live capture remain unverified. No model weights were downloaded or bundled.

Ad hoc preview signing, without Developer ID or notarization. System protections are unchanged.

Assets: Koto-0.1.0-alpha-13-arm64-preview.dmg, Koto-Chrome-0.1.3.zip, SHA256SUMS.txt, and the package JSON report.
