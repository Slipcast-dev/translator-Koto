[Русский](CHANGELOG.md) | **English**

# Changelog

## 0.1.0-alpha.15

Release: [Docs/RELEASE-0.1.0-alpha.15.md](Docs/RELEASE-0.1.0-alpha.15.md).

- Updates from GitHub Releases: a Settings section, check on demand, download, SHA-256 and signature verification, app replacement and relaunch.
- Engine status reflects the real state (model, key, language list).
- Chromium section: “Install” and “Remove” the extension; the switch only turns the bridge on or off.
- Safari extension and settings section.
- FAQ on getting Google and Yandex API keys.
- Fixed light/dark switching; “System” follows macOS.
- Fixed a `URLSession` leak in the cloud engines; faster local model start (APFS clone), runtime unload when idle, Live skips OCR on unchanged frames, the native host wakes less often, translation memory is written in the background, stale `/tmp/koto-*` leftovers are cleaned after a crash.
- Chrome 0.1.4 is unchanged.
