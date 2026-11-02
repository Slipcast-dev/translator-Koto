# Koto 0.1.0-alpha.16

**Русский.** Предварительная сборка для Apple Silicon, macOS 26+. Подпись ad hoc, без Apple Developer ID и notarization: macOS может блокировать запуск. Веса моделей в DMG не входят.

**Лицензия изменена:** вместо MIT действует [проприетарная лицензия Koto](https://github.com/Slipcast-dev/translator-Koto/blob/main/LICENSE) — изменять и распространять Koto без письменного согласия автора нельзя, использовать официальные релизы на своих устройствах можно. Копии, полученные раньше под MIT (до alpha.15 включительно), остаются на условиях MIT. Сторонние компоненты сохраняют свои лицензии. Лицензия показана в окне «О программе» и лежит в пакете (`LICENSE`).

Остальное без изменений относительно alpha.15: обновление из GitHub Releases, честный статус движков, расширения Chrome и Safari, FAQ по ключам, исправленная тема. Подробности: [CHANGELOG](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.md), состояние: [STATUS.md](STATUS.md).

Файлы выпуска собираются из исходников workflow GitHub и подтверждаются attestation:

```sh
gh attestation verify PATH --repo Slipcast-dev/translator-Koto \
  --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml \
  --source-ref refs/tags/v0.1.0-alpha.16
```

**English.** Preview build for Apple Silicon, macOS 26+. Ad hoc signed, without Apple Developer ID or notarization: macOS may block launch. The DMG contains no model weights.

**License changed:** the [Koto proprietary license](https://github.com/Slipcast-dev/translator-Koto/blob/main/LICENSE) replaces MIT — modifying or distributing Koto without the author's written consent is not allowed; using the official releases on your own devices is. Copies received earlier under MIT (up to and including alpha.15) stay under MIT. Third-party components keep their own licenses. The license is shown in the About window and shipped in the package (`LICENSE`).

Everything else is unchanged since alpha.15: updates from GitHub Releases, honest engine status, Chrome and Safari extensions, API key FAQ, fixed theme. Details: [CHANGELOG](https://github.com/Slipcast-dev/translator-Koto/blob/main/CHANGELOG.en.md); state: [STATUS.en.md](STATUS.en.md).

Release files are built from source by a GitHub workflow and carry attestations; verify with the command above.
