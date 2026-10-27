# Koto 0.1.0-alpha.14 · Chrome 0.1.4

## Русский

Включены исправления аудита alpha.13: origin и текст из одного документа, привязка вставки к documentId, начальные исключения сайтов, короткий путь browser socket, системный proxy, проверенный анонимный снимок модели, удаление get-task-allow из поставки и числовая bundle version. Actions/SwiftLint закреплены, добавлены CodeQL и приватные сообщения об уязвимостях.

Артефакты этого выпуска собираются из исходников и аттестуются GitHub Actions. Проверка каждого загруженного файла: `gh attestation verify PATH --repo Slipcast-dev/translator-Koto --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml`. SHA256SUMS проверяет байты; аттестация дополнительно связывает их с workflow и исходной ревизией. Старые alpha.13 файлы остаются историческими и не получают задним числом доказательства сборки.

Preview ad hoc, без Apple Developer ID/notarization. Аттестация не снимает Gatekeeper. App Sandbox не включён, legacy Keychain не гарантирует accessibility/device-only class. Qwen через новый снимок и длительный интерактивный Live отдельно не аттестованы; весов в поставке нет. Снимок требует дополнительное временное место размером с модель.

## English

Includes alpha.13 audit fixes for document origin/text capture, documentId-bound insertion, default site exclusions, long socket paths, system proxies, verified unlinked model snapshots, release debug-entitlement removal and numeric bundle version. Pins Actions/SwiftLint and adds CodeQL/private vulnerability reporting.

This release is built from source and attested by GitHub Actions. Verify each downloaded file with `gh attestation verify PATH --repo Slipcast-dev/translator-Koto --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml`. Earlier alpha.13 assets remain historical and are not retrospectively claimed as source-built/attested.

Ad hoc preview without Developer ID or notarization; provenance does not change Gatekeeper trust. App Sandbox, strict Data Protection Keychain semantics, actual Qwen generation through the new snapshot and extended interactive Live remain separate follow-up. No model weights are included.
