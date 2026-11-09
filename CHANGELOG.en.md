[Русский](CHANGELOG.md) | **English**

# Changelog

## 1.0.0

Release: [Docs/RELEASE-1.0.0.md](Docs/RELEASE-1.0.0.md).

- In-place live translation: Koto finds foreign text in the chosen region, detects each line’s language and draws the translation over the original line; the “Word under the cursor” mode shows a tooltip next to the word. The Koto window hides after choosing the region; stop with ⌃⌥⌘L again or from the Koto menu. Test builds are signed by identifier, so granted permissions survive a rebuild (grant them again once or press “Reset and ask again”).
- First stable release: no alpha markers, tag `v1.0.0`, file `Koto-1.0.0-20-arm64.dmg`. Signing is still ad hoc, without Developer ID or notarization.
- Selected-text translation also works where an app does not expose the selection through Accessibility: Koto briefly copies the selection (⌘C) and restores the previous clipboard contents. Password fields are never read.
- Screen region: the translation window appears immediately with a progress indicator, and a denied Screen Recording shows the permissions panel instead of nothing.
- Language auto-detection works on short words (“привет” no longer fails); extra labels removed from the main window; Live mode buttons show full names.
- Settings simplified: tabs General, Translation, Privacy, Browsers, Advanced; permissions are two rows with an “Allow…” button.

## 0.1.0-alpha.18

Release: [alpha.18](https://github.com/Slipcast-dev/translator-Koto/releases/tag/v0.1.0-alpha.18).

- The quick translation window no longer extends past the screen; the permissions panel has hints (a copy outside Applications, “Reset and ask again”). The release signature is tied to the identifier, so permissions survive updates.
- The localization check matches every string in the code with the catalog so the interface language is never mixed.

## 0.1.0-alpha.17

Release: [alpha.17](https://github.com/Slipcast-dev/translator-Koto/releases/tag/v0.1.0-alpha.17).

- Main window: all buttons in one macOS-style toolbar, grouped by function.
- Quick translation window: a permissions panel with statuses, an “Allow…” button, automatic continuation of the command after access is granted and a restart for screen recording; the panel appears only for access errors.
- Updates: a background check at launch (can be turned off), an offer with “Install”, “Later”, “Skip”, background preparation only with consent, a restart question with a “Later” option (applied when you quit).

## 0.1.0-alpha.16

Release: [alpha.16](https://github.com/Slipcast-dev/translator-Koto/releases/tag/v0.1.0-alpha.16).

- The license changed from MIT to the Koto proprietary license: modifying or distributing Koto without the author's written consent is not allowed. Copies up to and including alpha.15 stay under MIT.
- The license is shown in the About window; the package ships the new `LICENSE`.
- Everything else as in alpha.15.

## 0.1.0-alpha.15

Release: [alpha.15](https://github.com/Slipcast-dev/translator-Koto/releases/tag/v0.1.0-alpha.15).

- Updates from GitHub Releases: a Settings section, check on demand, download, SHA-256 and signature verification, app replacement and relaunch.
- Engine status reflects the real state (model, key, language list).
- Chromium section: “Install” and “Remove” the extension; the switch only turns the bridge on or off.
- Safari extension and settings section.
- FAQ on getting Google and Yandex API keys.
- Fixed light/dark switching; “System” follows macOS.
- Fixed a `URLSession` leak in the cloud engines; faster local model start (APFS clone), runtime unload when idle, Live skips OCR on unchanged frames, the native host wakes less often, translation memory is written in the background, stale `/tmp/koto-*` leftovers are cleaned after a crash.
- Chrome 0.1.4 is unchanged.
