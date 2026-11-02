[Русский](INSTALLATION.md) | **English**

# Installing Koto 0.1.0-alpha.16

Apple Silicon, macOS 26+. Release checks were performed on macOS 27.2; macOS 26 runtime remains untested.

1. Download the DMG and SHA256SUMS.txt from [alpha 16](https://github.com/Slipcast-dev/translator-Koto/releases/tag/v0.1.0-alpha.16).
2. Compare `shasum -a 256 Koto-0.1.0-16-arm64-preview-ci.dmg` with SHA256SUMS.txt.
3. Open the DMG and drag Koto.app into Applications.
4. Grant selection/OCR permissions through Koto Settings if needed.

The preview is signed ad hoc, without Developer ID or notarization; macOS may refuse to launch it. Scripts do not disable Gatekeeper or modify system trust. Alternatively, [build from source](BUILDING.en.md). Replacing an ad hoc build may require removing and re-adding the current Koto.app in the system permission lists, then restarting it. Password/Touch ID prompts must be confirmed by the Mac owner.

For Apple Translation, select the languages and click Translate. If Prepare languages appears, complete that explicit step. For optional Qwen, use the model installation button: [models](MODELS.en.md).

## Chrome 0.1.4

In Koto Settings (“Chromium browser”) click “Install extension for Chrome”: Koto registers the native host, places the extension files in `~/Library/Application Support/dev.slipcast.koto/ChromeExtension`, and opens that folder and `chrome://extensions`. Chrome requires confirmation: turn on Developer mode, click “Load unpacked” and choose the folder that opened. Extension ID: `bodbmpckhpjhkkhhadamlbkddaikilok`. The “Enable browser bridge” switch only turns the extension on or off and removes nothing; “Remove extension” deletes the host registration and the files (the extension itself is removed in Chrome). After updating Koto, click “Install extension for Chrome” again and reload the extension. You can still use BrowserExtension from the DMG or Koto-Chrome-0.1.4.zip manually. On an HTTP(S) tab, click Koto and choose an action; internal Chrome pages are excluded.

If Apple language resources are unavailable, choose the same pair in Koto and click Translate. Complete preparation if offered, then retry the browser action.

## Safari

The Safari extension is embedded in Koto.app (`Contents/PlugIns/Koto Safari.appex`). Move Koto to Applications, launch it once, then use “Turn on in Safari” in the “Safari browser” section (it opens Safari's extension settings). The preview build is not signed with an Apple Developer ID, so first enable Safari's Develop → Allow Unsigned Extensions; the choice resets when Safari quits. The extension uses the same bridge and the same switch as Chrome. **Not verified in a real Safari:** the build, embedding, signing and the bridge client are tested automatically, but enabling the extension and translating inside Safari need a manual check on your Mac.

## Updating

The “Update” section at the top of Settings shows the version, a short description and a “Check for updates” button. The check contacts GitHub Releases only when you click. If a newer version exists, a window shows its number, notes and size. “Install and restart” downloads the DMG, verifies its SHA-256 against the release's SHA256SUMS.txt, checks that the package is a newer, validly signed Koto, stages a copy next to the app, and after Koto quits replaces it and relaunches. The folder containing Koto.app must be writable. Every stage has a timeout and the download can be cancelled.

## Uninstall

Quit Koto and remove the app. If needed, remove the Chrome extension and its registration at `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.slipcast.koto.json`. Settings, memory and models in `~/Library/Application Support/dev.slipcast.koto`, and Keychain keys, are separate user data; removing the app should not silently destroy them.

## Interface language

Koto supports English and Russian, with English fallback. Choose its application language in macOS and restart Koto. Chrome selects its language independently. Your translation pair is preserved. Numbers follow the region. Explanations are requested in Koto's language, alternatives use the target language, and quotes remain in the original.
