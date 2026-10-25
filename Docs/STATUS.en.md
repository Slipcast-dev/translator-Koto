[Русский](STATUS.md) | **English**

# Status: 0.1.0-alpha.12 · Chrome 0.1.2

25 October 2026 · Slipcast-Dev · arm64/macOS 26+. Release checks: macOS 27.2, Xcode 27.1.

| Area | Verification and boundaries |
| --- | --- |
| Koto interface | ru/en, English fallback, 546 values and 12 language/region combinations |
| Chrome 0.1.2 | 37 messages per language, 13 logic tests, native ru/en page/selection/clear/cancel and errors |
| First requests | 6 fresh localized-app processes and 3 baseline processes, without manual warm-up |
| Dynamic data | 31 checks for numbers, sizes, plurals, RTL, instruction language and schema=1 |
| Regressions | 21 manual, 10 privacy, 15 installer, 15 capture, 22 quality contracts, 18 protocol and 23 integration checks |
| Distribution | Release 12, HFS+ DMG, separate Chrome ZIP, strict/deep codesign and checksum; no model weights |

[Release notes](RELEASE-0.1.0-alpha.12.md), [detailed acceptance, in Russian](LOCALIZATION-ACCEPTANCE.md), [release results](validation/release-12.json).

Build 11 localization checks are retained as history. The initially observed Working state did not reproduce as a hang: repeated first requests completed; no engine fix is claimed for that observation. Apple system services and caches were not restarted for these measurements.

Alpha limitations remain: macOS 26 runtime, Live endurance/energy/latency, sleep/wake, a broader application matrix, real Google/Yandex accounts, final speech/login acceptance, and Qwen semantic quality. Qwen was not installed for localization; instructions were checked, not generation.

Ad hoc preview signing, without Developer ID or notarization: macOS may block launch. Koto does not change system protections. An alpha publication is not independent linguistic certification or completion of these external checks.

[Historical alpha 11 tests](validation/results.json). System languages were not removed; missing-resource failures were simulated at the engine boundary.
