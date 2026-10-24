**Русский** | [English](INSTALLATION.en.md)

# Установка 0.1.0-alpha, build 11

Apple Silicon, macOS 26+. Фактически проверено на M1 / macOS 27.0.1.

1. Скачайте DMG и SHA256SUMS.txt из [релиза](https://github.com/Slipcast-dev/translator-Koto/releases/tag/v0.1.0-alpha.11).
2. Сверьте `shasum -a 256 Koto-0.1.0-alpha-11-arm64-preview.dmg` с checksum.
3. Откройте DMG, перенесите Koto.app в Applications.
4. Для выделения/OCR выдайте два доступа macOS через кнопки настроек Koto.

Preview имеет ad hoc подпись без Developer ID/notarization, macOS может отказать в запуске. Скрипты не отключают Gatekeeper и не изменяют доверие системы. Альтернатива — [сборка из исходников](BUILDING.md). После замены ad hoc сборки может потребоваться заново добавить текущий Koto.app в системные списки и перезапустить его. Пароль/Touch ID подтверждает владелец Mac.

Для Apple выберите языки и нажмите «Перевести». Если появится «Подготовить языки», выполните явную подготовку. Для необязательной Qwen используйте кнопку установки модели: [MODELS.md](MODELS.md).

## Chrome 0.1.1

Зарегистрируйте native host кнопкой настроек текущего Koto и включите мост. В `chrome://extensions` включите developer mode и Load unpacked папки BrowserExtension из DMG/проекта. ID: `bodbmpckhpjhkkhhadamlbkddaikilok`. После обновления source-папки перезагрузите расширение. На HTTP(S)-вкладке нажмите Koto и выберите действие; служебные страницы Chrome исключены.

При ошибке Apple-ресурсов выберите ту же пару в Koto и нажмите «Перевести». Если предложена подготовка — выполните её, затем повторите действие в браузере.

## Удаление

Завершите Koto и удалите app. При необходимости удалите расширение Chrome и регистрацию `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.slipcast.koto.json`. Настройки/память/модель в `~/Library/Application Support/dev.slipcast.koto` и ключи Keychain — отдельные пользовательские данные; удаление приложения не должно молча уничтожать их.
