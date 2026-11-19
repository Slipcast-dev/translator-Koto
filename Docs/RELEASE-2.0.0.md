# Koto 2.0.0

**Русский.** Выпуск для Apple Silicon, macOS 26+. Подпись ad hoc, без Apple Developer ID и notarization: macOS может блокировать запуск. Веса моделей в DMG не входят.

**Безопасность.** Встроенное обновление ставит только выпуск, у которого `SHA256SUMS.txt` подписан ключом Ed25519 разработчика; файлы берутся только из релизов этого репозитория, карантин при замене не снимается. Сборка и публикация релиза разделены: сборка идёт без прав записи. Служебные флаги запуска остались только в отладочной сборке; токен моста и ключ локального движка удаляются при выходе; native host проверяет подпись приложения перед запуском. Модель угроз описана в [SECURITY.md](../SECURITY.md).

**Надёжность и скорость.** Облачный перевод режет длинный текст и повторяет запрос при 429 и 5xx; один список языков для локальной модели и облака; запись файлов сбрасывается на диск. Расширение Chrome 0.1.5 переводит страницу по четыре фрагмента сразу. Число потоков локальной модели берётся по производительным ядрам, время простоя настраивается, загрузка модели возобновляется после обрыва, память переводов пишется пачками, проверка обновлений использует ETag.

Файлы выпуска собираются из исходников workflow GitHub и подтверждаются attestation:

```sh
gh attestation verify PATH --repo Slipcast-dev/translator-Koto \
  --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml \
  --source-ref refs/heads/main
```

**English.** Release for Apple Silicon, macOS 26+. Ad hoc signed, without Apple Developer ID or notarization: macOS may block launch. The DMG contains no model weights.

**Security.** The built-in updater installs only a release whose `SHA256SUMS.txt` is signed with the developer's Ed25519 key; files are taken only from this repository's releases, and quarantine is not stripped on replacement. Build and publish are separate jobs: the build runs without write access. Developer launch flags exist only in debug builds; the bridge token and the local engine key are removed on quit; the native host verifies the app signature before launching it. The threat model is in [SECURITY.en.md](../SECURITY.en.md).

**Reliability and speed.** Cloud translation splits long text and retries on 429 and 5xx; one language list for the local model and the cloud; file writes are flushed to disk. Chrome extension 0.1.5 translates a page four fragments at a time. Local model threads follow the performance cores, the idle time is configurable, model download resumes after an interruption, translation memory is written in batches, and update checks use ETag.

Release files are built from source by a GitHub workflow and carry attestations; verify with the command above.
