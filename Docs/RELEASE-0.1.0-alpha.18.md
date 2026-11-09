# Koto 0.1.0-alpha.18

**Русский.** Предварительная сборка для Apple Silicon, macOS 26+. Подпись ad hoc, без Apple Developer ID и notarization: macOS может блокировать запуск. Веса моделей в DMG не входят.

**Исправления.** Окно быстрого перевода больше не раздувается за пределы экрана. Панель разрешений подсказывает, что делать, если Koto включён в списке, но доступ не появляется: запуск из «Программ» (не из загрузки или образа) и кнопка «Сбросить и запросить заново». Подпись выпуска теперь привязана к идентификатору приложения, а не к хэшу сборки, поэтому разрешения macOS сохраняются при обновлениях (при переходе на эту версию доступ нужно выдать один раз заново). Интерфейс везде на одном языке: проверка в CI сопоставляет все строки в коде с каталогом переводов. Подробности: [CHANGELOG](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.md), состояние: [STATUS.md](STATUS.md).

Файлы выпуска собираются из исходников workflow GitHub и подтверждаются attestation:

```sh
gh attestation verify PATH --repo Slipcast-dev/translator-Koto \
  --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml \
  --source-ref refs/heads/main
```

**English.** Preview build for Apple Silicon, macOS 26+. Ad hoc signed, without Apple Developer ID or notarization: macOS may block launch. The DMG contains no model weights.

**Fixes.** The quick translation window no longer grows past the screen. The permissions panel explains what to do when Koto is turned on in the list but access does not appear: run it from Applications (not from a download or disk image) and the “Reset and ask again” button. The release signature is now tied to the app identifier instead of the build hash, so macOS permissions survive updates (grant access once more when moving to this version). The interface uses one language everywhere: a CI check matches every string in the code with the translation catalog. Details: [CHANGELOG](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.en.md); state: [STATUS.en.md](STATUS.en.md).

Release files are built from source by a GitHub workflow and carry attestations; verify with the command above.
