[Русский](BUILDING.md) | **English**

# Building, checking and releasing

You need Apple Silicon, Xcode with a macOS SDK supported by the project, Swift 6 and Python 3. Deployment target 26.0; Swift 6.2+ compiler (Xcode 26+), Swift 6 language mode.

## Building

```sh
git clone --recurse-submodules https://github.com/Slipcast-dev/translator-Koto.git
cd translator-Koto
./script/build_local_runtime.sh
./script/build_native_host.sh
KOTO_CONFIGURATION=Release ./script/build_and_run.sh --build-only
python3 script/package_release.py
```

- **Runtime.** llama.cpp is pinned by the submodule and `ThirdParty/llama-lock.json` to `7894e8b92481a8bb8ffe94f73b656ffe0dd01e10`; `verify_runtime_source.py` checks the tree SHA-256. GitHub source archives omit the submodule: if the tree is missing, `build_local_runtime.sh` fetches the pinned upstream. cmake and ninja are installed into `build/tooling`; the runtime is built statically with Metal. No weights are downloaded. Binary runtime resources are excluded from Git and restored by the commands above. The DMG already contains the runtime and needs neither Xcode nor Python.
- **Targets.** The `Koto` app and the `Koto Safari` extension (folder `SafariExtension/`, embedded into `Koto.app/Contents/PlugIns`; the popup and localization are shared with `BrowserExtension/`).
- **Version.** `CFBundleShortVersionString` is numeric (`MARKETING_VERSION`), an empty `KotoReleaseChannel` means a stable release, and the build number is `CURRENT_PROJECT_VERSION` in `Config/Product.xcconfig`. Do not set `SWIFT_VERSION` to a compiler minor version: 6.0 denotes the language mode.
- **Signing.** The release is ad hoc signed; Developer ID and notarization are a separate process. Do not disable system protections for testing.
- **Your own certificate (optional).** `Tools/CreateSigningIdentity.swift` creates a self-signed certificate with a non-extractable key in the Keychain; `python3 script/package_release.py --identity <certificate SHA1>` pins macOS permissions to its fingerprint. The release workflow stays ad hoc: no key is passed to CI. The first switch from ad hoc requires granting permissions again. This path has not been re-tested on a live system since the change.
- **Model.** The runtime starts from an anonymous verified snapshot through an inherited stdin; on APFS the snapshot is an instant copy-on-write clone needing no extra space, otherwise a full copy is made (temporary space equal to the model size). The runtime is unloaded after 10 minutes without requests.

## Layout

`App`, `Features` — UI and coordination; `Core` — contracts, privacy and protocol; `Services` — engines, Accessibility, OCR, bridge, updates; `NativeHost`, `NativeTools` — first-party host and launcher; `BrowserExtension` — Chrome MV3; `SafariExtension` — the Safari extension; `Resources/LocalModels` — catalog and licenses only; `Tests`, `script` — checks and build.

## Checks

```sh
python3 script/validate_repository.py
python3 script/validate_localization.py
bash script/test_swift_ci.sh
KOTO_TEST_HOOKS=1 bash script/build_native_host.sh
python3 script/test_bridge_integration.py
build/tooling/swiftlint/swiftlint lint --strict --config .swiftlint.yml
```

- `test_swift_ci.sh` runs 14 deterministic runs: 10 shell suites (regressions, manual translation, capture, privacy, model installation, quality, bridge protocol, runtime transport, localization dynamics, cloud policy), the direct Live and settings-migration harnesses, the update test on real DMGs and the Safari bridge client test, plus a Python check of the long socket path. No model or screen permissions are needed.
- Install SwiftLint 0.65.1 with `bash script/install_swiftlint.sh` (the archive SHA-256 is verified).
- The real Apple smoke test (`./script/test_apple_translation.sh`) and the bridge integration need prepared system EN/RU resources. Missing resources are an environment state, not a passing test. Qwen tests need a user-installed model.
- Localization: after the Release build run `python3 script/test_localization.py` and `./script/test_localization_dynamics.sh`; Chrome: `node --experimental-vm-modules --test Tests/BrowserLocalizationTests.mjs`; catalogs: `python3 -m unittest discover -s Tests -p LocalizationCatalogTests.py`. See [LOCALIZATION.md](LOCALIZATION.md).
- Package: after `package_release.py`, mount the DMG and run `python3 script/verify_localized_package.py /path/to/mounted/Koto`.
- First request without warm-up: `python3 script/test_browser_cold_start.py --app build/DerivedData/Build/Products/Release/Koto.app --language en` (needs system EN/RU resources; no model download, no cloud).
- For interface snapshots the app accepts `--koto-open-settings` (the Settings window), `--koto-capture-selection` and `--koto-capture-region` (start a capture like the hotkey; without permissions they show the access panel).

GitHub CI on macOS 26 builds the app unsigned and runs SwiftLint and `test_swift_ci.sh`; CodeQL and Dependency Review run separately. Dependabot checks GitHub Actions and the llama.cpp submodule weekly; a submodule update needs a runtime check.

## Release

Before publishing, the workflow repeats the repository and localization checks, extension tests, SwiftLint, the build and `test_swift_ci.sh`. The publish job runs only from `main` in the `release` environment. **Configure on GitHub:** Settings → Environments → release → Required reviewers and restrict it to `main`; preferably move the `KOTO_UPDATE_SIGNING_KEY` secret from repository secrets into that environment. Without these settings the environment is created unprotected.

**Rotating the update key.** `KOTO_UPDATE_PUBLIC_KEY` accepts up to four comma-separated keys. First release a version with “old,new”, signed with the old key (listed first). Once users have updated, list the new key first, replace the secret, and drop the old key in a following release. Versions older than this change understand a single key only.

Releases are automatic. In a pull request raise `CURRENT_PROJECT_VERSION` in `Config/Product.xcconfig` and add `Docs/RELEASE-<version>.md` (for example `RELEASE-3.0.0.md`, bilingual notes, absolute links or links to neighbouring docs only). After the merge into `main` the workflow `.github/workflows/build-artifacts.yml`:

1. builds the app from source on macOS 26;
2. packages the DMG, the Chrome extension ZIP and `SHA256SUMS.txt`;
3. attests the files with GitHub/Sigstore;
4. creates the tag `v<version>` and a release with the notes.

If a release of that version already exists the build is skipped; the same workflow can also be run manually (the workflow creates the `v*` tag itself and that tag does not start a second build). The workflow does not delete earlier releases. The [koto-website](https://github.com/Slipcast-dev/koto-website) site picks up the latest release on its own and updates the download links. Verify a file with `gh attestation verify PATH --repo Slipcast-dev/translator-Koto --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml`. An attestation binds the files to a source revision and workflow; it does not replace an Apple Developer ID or notarization.

Changes reach `main` through pull requests with auto-merge enabled after the required checks.

## Update signing key

The in-app updater only installs a release whose `SHA256SUMS.txt` carries a valid Ed25519 signature (`SHA256SUMS.txt.sig`). The public key is `KOTO_UPDATE_PUBLIC_KEY` in `Config/Product.xcconfig`; the private key is the repository secret `KOTO_UPDATE_SIGNING_KEY` (base64, 32 bytes) and is used only by the `publish` job. Generate a pair with `swift script/update_signing.swift generate`. Rotating the key requires a manual install of one release, because installed copies trust the old public key.
