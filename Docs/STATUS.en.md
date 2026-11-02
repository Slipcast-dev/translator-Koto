[Русский](STATUS.md) | **English**

# Koto 0.1.0-alpha.14 · Chrome 0.1.4

27 October 2026 · Slipcast-Dev · arm64/macOS 26+. Release checks: macOS 27.2, Xcode 27.1.

## Current state

Alpha.14 is published: [release notes](RELEASE-0.1.0-alpha.14.md). External audit fixes are included; the artifact workflow builds the delivered bytes from source and attests them.

Source build and all four artifact attestations are **verified**, constrained to tag v0.1.0-alpha.14 and source commit 33cdfea: [workflow](https://github.com/Slipcast-dev/translator-Koto/actions/runs/40428747991), [verification report](validation/release-14.json). Mounted DMG and codesign passed. Published alpha.12 and alpha.13 remain historical.

## After alpha.14 (unreleased)

Commits `4f66c67` (`URLSession` leak) and `21d6660` (optimizations: APFS-clone model snapshot, runtime unload, Live OCR skip, less frequent native host polling). Version and build stay 0.1.0-alpha / 14, so the local test build (`…-test-20261102`) differs from the published alpha.14 artifacts and has no attestation. Passed locally: `test_swift_ci.sh` (11 Swift runs and the long-path check), bridge integration 23/23, SwiftLint `--strict`, Debug and Release builds. Speed and energy gains were not measured; real Qwen generation with the new snapshot and unload was not verified.

## Limitations

- Ad hoc preview signing, without Developer ID or notarization: macOS may block launch. Koto does not change system protections.
- Not verified: macOS 26 runtime, Live endurance/energy/latency, sleep/wake, a broader application matrix, real Google/Yandex accounts, final speech/login acceptance, Qwen semantic quality.
- Qwen was not installed for localization checks: instructions were checked, not generation. Actual Qwen generation over the Unix transport is also unverified.
- Notarization, full App Sandbox and Data Protection Keychain require separate follow-up.
- An alpha publication is not independent linguistic certification or completion of these checks.

## External audit · 27 October

[Review of all 11 items, in Russian](AUDIT-2026-10-27.md). Fixes browser origin/navigation, long bridge socket paths, proxy handling and verified model descriptor loading; pins Actions/SwiftLint and adds CodeQL/provenance workflows. Private Vulnerability Reporting is enabled.

## Alpha.13 · 25 October

MIT copyright Slipcast-Dev, community guidelines, AF_UNIX runtime identity, DNS exclusion normalization, OCR resume and catalogue generation fixes. Release build, ten Swift harnesses, 76 Swift files linted, 9 Python and 13 JavaScript tests passed locally. [Release notes](RELEASE-0.1.0-alpha.13.md).

Five findings against alpha.12 (runtime endpoint trust, excluded DNS domain endpoint, OCR Pause/Resume, stale engine catalogue, missing Swift in CI) were verified and fixed: [changes, commands and verification limits](REVIEW-FIXES-2026-10-25.md).

Clean remote build, SwiftLint, and all ten Swift harnesses on macOS 26 arm64 **passed**: [CI](https://github.com/Slipcast-dev/translator-Koto/actions/runs/40202546241). The initial missing BrowserBridge failure was fixed by building the native host before Xcode. Dependency Review also passed on a Dependabot PR. This verifies builds and deterministic contracts on macOS 26, not complete interactive GUI/Live/Qwen acceptance.

## Alpha.12 · localization, 25 October

| Area | Verification and boundaries |
| --- | --- |
| Koto interface | ru/en, English fallback, 546 values and 12 language/region combinations |
| Chrome 0.1.2 | 37 messages per language, 13 logic tests, native ru/en page/selection/clear/cancel and errors |
| First requests | 6 fresh localized-app processes and 3 baseline processes, without manual warm-up |
| Dynamic data | 31 checks for numbers, sizes, plurals, RTL, instruction language and schema=1 |
| Regressions | 21 manual, 10 privacy, 15 installer, 15 capture, 22 quality contracts, 18 protocol and 23 integration checks |
| Distribution | Release 12, HFS+ DMG, separate Chrome ZIP, strict/deep codesign and checksum; no model weights |

[Release notes](RELEASE-0.1.0-alpha.12.md), [detailed acceptance, in Russian](LOCALIZATION-ACCEPTANCE.md), [release results](validation/release-12.json).

## Alpha.11 · history

[Alpha 11 tests](validation/results.json). System languages were not removed; missing-resource failures were simulated at the engine boundary. The initially observed Working state did not reproduce as a hang: repeated first requests completed; no engine fix is claimed for that observation. Apple system services and caches were not restarted for these measurements.
