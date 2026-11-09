# Koto 0.1.0-alpha.17

**Русский.** Предварительная сборка для Apple Silicon, macOS 26+. Подпись ad hoc, без Apple Developer ID и notarization: macOS может блокировать запуск. Веса моделей в DMG не входят.

**Что нового.** Все кнопки главного окна собраны в одной панели инструментов в стиле macOS и разделены по смыслу: захват (выделение, область экрана, Live), перевод, результат (копировать, озвучить, остановить), очистка, пояснение, настройки. Окно быстрого перевода показывает понятную панель разрешений: что нужно, выдано ли, кнопка «Разрешить…» открывает нужный раздел настроек, статусы обновляются сами, а исходная команда продолжается автоматически после выдачи доступа. Koto проверяет обновления при запуске в фоне (можно отключить в настройках), предлагает установить, загружает и готовит обновление только с вашего согласия, не прерывая работу, а перед перезапуском спрашивает: «Перезапустить сейчас» или «Позже» (тогда обновление применится при выходе). Подробности: [CHANGELOG](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.md), состояние: [STATUS.md](STATUS.md).

Файлы выпуска собираются из исходников workflow GitHub и подтверждаются attestation:

```sh
gh attestation verify PATH --repo Slipcast-dev/translator-Koto \
  --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml \
  --source-ref refs/heads/main
```

**English.** Preview build for Apple Silicon, macOS 26+. Ad hoc signed, without Apple Developer ID or notarization: macOS may block launch. The DMG contains no model weights.

**What's new.** All buttons of the main window now live in one macOS-style toolbar, grouped by purpose: capture (selection, screen region, Live), translation, result (copy, speak, stop), clear, explanation, settings. The quick translation window shows a clear permissions panel: what is needed, whether it is granted, an “Allow…” button that opens the right Settings pane, statuses that refresh on their own, and the original command continues automatically once access is granted. Koto checks for updates in the background at launch (can be turned off in Settings), offers to install, and downloads and prepares the update only with your consent without interrupting your work; before restarting it asks: “Restart now” or “Later” (the update is then applied when you quit). Details: [CHANGELOG](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.en.md); state: [STATUS.en.md](STATUS.en.md).

Release files are built from source by a GitHub workflow and carry attestations; verify with the command above.
