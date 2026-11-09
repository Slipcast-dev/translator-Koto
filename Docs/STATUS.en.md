[Русский](STATUS.md) | **English**

# Koto 1.0.1 · Chrome 0.1.4

Slipcast-Dev · arm64/macOS 26+. Release checks ran on macOS 27.2 / Xcode 27.

## State

Release 1.0.1: ad hoc signing, without Developer ID or notarization — macOS may block launch. Release files are built from source by a GitHub workflow and carry attestations ([release notes](RELEASE-1.0.1.md)). The Qwen model is not shipped; it is installed with a button in Settings.

## License and releases

Koto is under a [proprietary license](../LICENSE): modifying or distributing it without the author's written consent is not allowed, while using the official releases on your own devices is (copies up to and including alpha.15 stay under MIT). Releases are automatic: changing `CURRENT_PROJECT_VERSION` on `main` triggers the build, attestation and release publication, and the website picks up the latest release on its own ([process](BUILDING.en.md#release)).

## Automated checks

`bash script/test_swift_ci.sh` (13 runs: Swift suites, the update test on real DMGs, the Safari bridge client, the long socket path check), bridge integration (`script/test_bridge_integration.py`), SwiftLint `--strict`, repository and localization validation (`script/validate_repository.py`, `script/validate_localization.py`), Chrome tests. GitHub CI runs the macOS 26 build, SwiftLint, the Swift suites, CodeQL and Dependency Review.

## Not verified

- Full interactive acceptance on macOS 26, Live (endurance, energy, latency), sleep/wake, a broad application matrix.
- The Safari extension inside Safari (build, embedding, signing and the bridge client are tested; enabling the extension and translating in Safari are not). The build needs “Allow Unsigned Extensions” in Safari.
- Real Google and Yandex accounts, speech, login launch.
- Real Qwen generation and semantic quality over the current transport.
- An end-to-end update through live GitHub: possible once a release newer than the installed one exists.
- The intermittent internal cause of the first-call Apple Translation failure is unknown; Koto handles the failure.
- Developer ID/notarization, a full App Sandbox and strict Data Protection Keychain guarantees need a separate external step.
