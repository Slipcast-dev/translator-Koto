[Русский](CHANGELOG.md) | **English**

# Changelog

## Unreleased (after alpha.14)

Fixed a `URLSession` leak in the cloud engines (one shared session). The model snapshot is now an APFS clone instead of a full copy; the runtime unloads after 10 minutes without requests; Live skips OCR when the frame is unchanged; the native host wakes less often when idle; the bridge removes `bridge.token` on stop. New: an “Update” section in Settings (check, download and automatic install from GitHub Releases with SHA-256 and signature checks); an honest engine status instead of a constant “Ready”; a simplified Chromium section (install/remove the extension, the switch only turns the bridge on); a Safari extension and settings section (build verified, behaviour in Safari not tested); an FAQ on getting Google and Yandex API keys; fixed light/dark switching and following the system theme. Documentation aligned with the code. Version and build are unchanged (0.1.0-alpha, build 14): the local test build differs from the published alpha.14.

## 0.1.0-alpha.14 — 2026-10-27

Audit fixes and source-built GitHub artifact attestations; Chrome 0.1.4. [Release notes](Docs/RELEASE-0.1.0-alpha.14.md).

## 0.1.0-alpha.13 — 2026-10-25

Fixes four runtime/privacy/concurrency issues; adds Swift CI, SwiftLint, Dependabot, Dependency Review, licensing and community guidelines. Updates the installer and Chrome 0.1.3. See [release notes](Docs/RELEASE-0.1.0-alpha.13.md).

## 0.1.0-alpha.12 — 2026-10-25

Koto ru/en and Chrome 0.1.2 localization: regional numbers, plurals, RTL, explanation language and stable error codes. Bilingual model-free HFS+ installer, separate extension ZIP and catalog checks in CI. [Release notes and limitations](Docs/RELEASE-0.1.0-alpha.12.md).


## Documentation update after alpha.11

Russian and English README, core documentation, contribution/security guidance and release notes; bilingual issue forms and language-switch links. No application binary changes.

## 0.1.0-alpha.11 — 2026-10-24

The first public Koto alpha by Slipcast-Dev: Swift 6/SwiftUI/AppKit, Koto Cat, Apple Translation, AX/OCR, Live and Chrome bridge; optional Qwen with one-button installation and no weights in Git/app/DMG.

Fixed native-host idle timeout and runtime notInstalled recovery while preserving the language pair. Extension 0.1.1 explains Apple resource unavailability. Updated documentation, banner and release checksum. [Verification boundaries](Docs/STATUS.en.md).
