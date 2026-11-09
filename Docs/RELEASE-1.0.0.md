# Koto 1.0.0

**Русский.** Выпуск для Apple Silicon, macOS 26+. Подпись ad hoc, без Apple Developer ID и notarization: macOS может блокировать запуск. Веса моделей в DMG не входят.

**Что нового.** Перевод выделенного текста работает и там, где приложение не отдаёт выделение через Универсальный доступ: Koto коротко копирует выделенное и возвращает прежний буфер обмена (парольные поля не читаются). Область экрана показывает окно с индикатором сразу, а отказ в записи экрана — панель разрешений. Живой перевод работает по наведению: выберите область и задержите курсор на слове, перевод появится рядом (режим «Вся область» сохранён). Настройки упрощены до пяти вкладок, разрешения — две строки с кнопкой «Разрешить…». Подробности: [CHANGELOG](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.md), состояние: [STATUS.md](STATUS.md).

Файлы выпуска собираются из исходников workflow GitHub и подтверждаются attestation:

```sh
gh attestation verify PATH --repo Slipcast-dev/translator-Koto \
  --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml \
  --source-ref refs/heads/main
```

**English.** Release for Apple Silicon, macOS 26+. Ad hoc signed, without Apple Developer ID or notarization: macOS may block launch. The DMG contains no model weights.

**What is new.** Selected-text translation also works where an app does not expose the selection through Accessibility: Koto briefly copies the selection and restores the previous clipboard (password fields are never read). The screen region shows the window with a progress indicator at once, and a denied Screen Recording shows the permissions panel. Live translation works by hover: choose a region and hold the cursor over a word, the translation appears next to it (the “Whole region” mode is kept). Settings are reduced to five tabs, and permissions are two rows with an “Allow…” button. Details: [CHANGELOG](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.en.md); state: [STATUS.en.md](STATUS.en.md).

Release files are built from source by a GitHub workflow and carry attestations; verify with the command above.
