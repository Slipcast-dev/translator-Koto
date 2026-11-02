# Koto 0.1.0-alpha.15

**Русский.** Предварительная сборка для Apple Silicon, macOS 26+. Подпись ad hoc, без Apple Developer ID и notarization: macOS может блокировать запуск. Веса моделей в DMG не входят.

Новое: обновление из GitHub Releases прямо из настроек; честный статус движков; упрощённый раздел Chromium; расширение Safari (встроено в приложение); FAQ по ключам Google и Yandex; исправленная смена темы; исправление утечки памяти в облачных движках и ускорения запуска. Подробности: [CHANGELOG.md](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.md), состояние и ограничения: [STATUS.md](STATUS.md).

Файлы выпуска собираются из исходников workflow GitHub и подтверждаются attestation. Проверка:

```sh
gh attestation verify PATH --repo Slipcast-dev/translator-Koto \
  --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml \
  --source-ref refs/tags/v0.1.0-alpha.15
```

**English.** Preview build for Apple Silicon, macOS 26+. Ad hoc signed, without Apple Developer ID or notarization: macOS may block launch. The DMG contains no model weights.

New: updates from GitHub Releases inside Settings; honest engine status; a simpler Chromium section; a Safari extension (embedded in the app); an FAQ on Google and Yandex keys; fixed theme switching; a memory-leak fix in the cloud engines and faster start-up. Details: [CHANGELOG.en.md](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.en.md); state and limitations: [STATUS.en.md](STATUS.en.md).

Release files are built from source by a GitHub workflow and carry attestations; verify with the command above.
