[Русский](STATUS.md) | **English**

# Status: 0.1.0-alpha.11

24 October 2026 · Slipcast-Dev · arm64/macOS 26+. Runtime testing: M1/macOS 27.0.1.

| Area | Verification and boundaries |
| --- | --- |
| Manual translation | 21 state-machine tests, 3 real Apple scenarios |
| Recovery | Build 11 offers explicit preparation with the resolved pair after runtime notInstalled; the regression test failed before the fix |
| Chrome | 18 protocol and 22 AF_UNIX/native integrations; main real popup page/selection/clear/unsupported scenarios on build 9 |
| Native host idle | Queue deadline fixed; a real 20-second pause in Chrome passed on build 10 |
| AX/OCR | Physical hotkeys/control phrase confirmed by the user on build 9; build 10 TCC statuses checked after rebinding/restart |
| Model installer | 15 isolated checks, real-file SHA/atomic activation; separate real partial HTTPS download/cancellation |
| Package | Release 11, strict/deep codesign, hdiutil verify, no model weights |

[Machine-readable results](validation/results.json). Missing-resource errors were simulated only at the engine boundary; system languages were not removed. The new recovery branch has not been declared tested with physically removed languages.

Open limitations: intermittent internal Apple framework failure (root cause unknown; recovery handling fixed); macOS 26 runtime; Live endurance/energy/latency; sleep/wake; a broader application matrix; real Google/Yandex accounts; final speech/login acceptance; incorrect cloud-engine idle label; Qwen semantic errors; no Developer ID/notarization.

An alpha publication does not mean these checks are complete. At the author's request, the system copy of Koto was removed; the app/DMG remain only in the local project. Old reports are archived locally outside Git; this documentation describes the current release.
