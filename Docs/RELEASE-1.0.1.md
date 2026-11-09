# Koto 1.0.1

**Русский.** Выпуск для Apple Silicon, macOS 26+. Подпись ad hoc, без Apple Developer ID и notarization: macOS может блокировать запуск. Веса моделей в DMG не входят.

**Что нового.** Живой перевод работает на месте: Koto находит иностранный текст в выбранной области, определяет язык каждой строки и рисует перевод поверх исходной строки; режим «Слово под курсором» показывает подсказку рядом со словом. Окно Koto после выбора области скрывается, остановка — повторное ⌃⌥⌘L или меню Koto. Главное окно: кнопки движков отдельные и по центру, «Перевести» и «Очистить» стоят под полем ввода. Автоопределение языка работает на коротких словах. Перевод выделенного текста работает и там, где приложение не отдаёт выделение (⌘C с восстановлением буфера). Разрешения сохраняются при обновлениях.

**Безопасность и скорость.** Менеджеры паролей (Пароли, Связка ключей, 1Password, Bitwarden, KeePassXC, LastPass, Dashlane) исключены по умолчанию; копирование выделенного пропускается при большом буфере обмена и не записывается менеджерами буфера как новая копия; распознавание текста прогревается при запуске; перевод строк идёт пачками; опрос мыши реже вне области; монтирование образа обновления повторяется при сбое. Подробности: [CHANGELOG](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.md), состояние: [STATUS.md](STATUS.md).

Файлы выпуска собираются из исходников workflow GitHub и подтверждаются attestation:

```sh
gh attestation verify PATH --repo Slipcast-dev/translator-Koto \
  --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml \
  --source-ref refs/heads/main
```

**English.** Release for Apple Silicon, macOS 26+. Ad hoc signed, without Apple Developer ID or notarization: macOS may block launch. The DMG contains no model weights.

**What is new.** Live translation works in place: Koto finds foreign text in the chosen region, detects each line’s language and draws the translation over the original line; a “Word under the cursor” mode shows a tooltip next to the word. The Koto window hides after choosing the region; stop with ⌃⌥⌘L again or from the Koto menu. Main window: engine buttons are separate and centred, “Translate” and “Clear” sit under the input field. Language auto-detection works on short words. Selected-text translation also works where an app does not expose the selection (⌘C with clipboard restore). Permissions survive updates.

**Security and speed.** Password managers (Passwords, Keychain Access, 1Password, Bitwarden, KeePassXC, LastPass, Dashlane) are excluded by default; the selection copy is skipped for a large clipboard and is not recorded by clipboard managers as a new copy; text recognition is warmed up at launch; lines are translated in batches; mouse polling is slower outside the region; mounting the update image is retried on failure. Details: [CHANGELOG](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.en.md); state: [STATUS.en.md](STATUS.en.md).

Release files are built from source by a GitHub workflow and carry attestations; verify with the command above.
