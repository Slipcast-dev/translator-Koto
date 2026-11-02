[Русский](CHANGELOG.md) | **English**

# Changelog

## 0.1.0-alpha.16

Release: [Docs/RELEASE-0.1.0-alpha.16.md](Docs/RELEASE-0.1.0-alpha.16.md).

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
