[Русский](INSTALLATION.md) | **English**

# Installation: 0.1.0-alpha, build 11

Apple Silicon, macOS 26+. Runtime checks were performed on M1 / macOS 27.0.1.

1. Download the DMG and SHA256SUMS.txt from the [release](https://github.com/Slipcast-dev/translator-Koto/releases/tag/v0.1.0-alpha.11).
2. Compare `shasum -a 256 Koto-0.1.0-alpha-11-arm64-preview.dmg` with the published checksum.
3. Open the DMG and drag Koto.app into Applications.
4. For selection capture/OCR, grant both macOS permissions using the buttons in Koto Settings.

The preview is signed ad hoc, without Developer ID or notarization; macOS may refuse to launch it. Scripts do not disable Gatekeeper or modify system trust. Alternatively, [build from source](BUILDING.en.md). Replacing an ad hoc build may require removing and re-adding the current Koto.app in the system permission lists, then restarting it. Password/Touch ID prompts must be confirmed by the Mac owner.

For Apple Translation, select the languages and click Translate (Перевести). If Prepare languages (Подготовить языки) appears, complete that explicit step. For optional Qwen, use the model installation button: [models](MODELS.en.md).

## Chrome 0.1.1

Register the native host using the current Koto app's Settings button and enable the bridge. In `chrome://extensions`, enable Developer mode and Load unpacked from the BrowserExtension folder in the DMG/project. Extension ID: `bodbmpckhpjhkkhhadamlbkddaikilok`. Reload the extension after updating its source folder. On an HTTP(S) tab, click Koto and choose an action; internal Chrome pages are excluded.

If Apple language resources are unavailable, choose the same pair in Koto and click Translate. Complete preparation if offered, then retry the browser action.

## Uninstall

Quit Koto and remove the app. If needed, remove the Chrome extension and its registration at `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.slipcast.koto.json`. Settings, memory and models in `~/Library/Application Support/dev.slipcast.koto`, and Keychain keys, are separate user data; removing the app should not silently destroy them.
