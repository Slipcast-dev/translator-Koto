[Русский](BUILDING.md) | **English**

# Build and verification

Requires Apple Silicon, Xcode with a macOS SDK supported by the project, Swift 6 and Python 3. Deployment target: 26.0; tested runtime: macOS 27.0.1. Running on macOS 26 remains a separate pending check.

```sh
git clone --recurse-submodules https://github.com/Slipcast-dev/translator-Koto.git
cd translator-Koto
./script/build_local_runtime.sh
./script/build_native_host.sh
KOTO_CONFIGURATION=Release ./script/build_and_run.sh --build-only
python3 script/package_release.py
```

llama.cpp is pinned by the submodule and ThirdParty/llama-lock.json to `7894e8b92481a8bb8ffe94f73b656ffe0dd01e10`; verify_runtime_source.py verifies the source tree's SHA-256 hashes. GitHub source archives omit submodules: if the tree is absent, build_local_runtime.sh fetches the pinned upstream revision. cmake/ninja are installed into build/tooling; the runtime is built statically with Metal. Weights are not downloaded. Runtime binaries are excluded from Git and recreated by the commands above. The DMG already contains the runtime and does not require Xcode/Python.

```sh
python3 script/validate_repository.py
./script/test_manual_translation.sh
./script/test_capture.sh
./script/test_product_privacy.sh
./script/test_model_installation.sh
./script/test_quality_behaviors.sh
./script/test_bridge_protocol.sh
python3 script/test_bridge_integration.py
./script/test_apple_translation.sh
```

Real Apple smoke and transport integration tests require prepared EN/RU resources. Missing resources are an environment condition, not a passing test. Qwen tests require a user-installed model and do not automatically download one.

App/Features: UI and coordination; Core: contracts, privacy and protocol; Services: engines/AX/OCR/bridge; NativeHost/NativeTools: host/launcher; BrowserExtension: MV3; Resources/LocalModels: catalog/licenses only; Tests/script: verification/build. Local products and archived reports are excluded under build/.

The preview uses ad hoc signing. Developer ID/notarization is a separate process. Do not disable system protections for testing; keys and original text must not appear in logs.

## macOS localization checks

After the Release build, run `python3 script/test_localization.py` and `./script/test_localization_dynamics.sh`. They check compiled ru/en resources, 12 language/region combinations, plurals, numbers, RTL, explanation instruction language and schema=1. No additional Python packages or model are required. See the [dynamic localization report, in Russian](LOCALIZATION-DYNAMICS.md) for scope and limitations.

## Chrome localization checks

Run `node --experimental-vm-modules --test Tests/BrowserLocalizationTests.mjs`, then `./script/test_bridge_protocol.sh`. No npm packages are required. Node.js is needed only for tests. See the [Chrome localization report, in Russian](LOCALIZATION-CHROME.md) for the distinction between logic tests and native browser checks.

CI: `python3 script/validate_localization.py` and `python3 -m unittest discover -s Tests -p LocalizationCatalogTests.py`. Local package: `python3 script/package_release.py --artifact-suffix localization-hfs`; after mounting, run `python3 script/verify_localized_package.py /path/to/mounted/Koto`.

First request without manual warm-up: quit Koto and run `python3 script/test_browser_cold_start.py --app build/DerivedData/Build/Products/Release/Koto.app --language en`. It requires installed system EN/RU resources, downloads no model and uses no cloud engine.

## CI / static analysis

`bash script/test_swift_ci.sh` runs ten deterministic Swift harnesses. `swiftlint lint --strict --config .swiftlint.yml` checks correctness rules without formatting unrelated code. Install the pinned SwiftLint 0.65.1 with `bash script/install_swiftlint.sh` (archive SHA-256 is verified); run `build/tooling/swiftlint/swiftlint lint --strict --config .swiftlint.yml`. GitHub Actions builds the app on macOS 26 arm64 and runs the same harnesses and lint rules. Dependabot monitors GitHub Actions and the llama.cpp submodule weekly; submodule updates require review and regeneration of the source locks before merging. Dependency Review checks newly introduced dependencies on pull requests. Pinned CMake/Ninja build tools and the model catalog are outside these automatic dependency checks.

## Проверяемое происхождение артефактов / Artifact provenance

`.github/workflows/build-artifacts.yml` builds preview artifacts from source on macOS 26 for a tag or manual workflow run and generates GitHub/Sigstore attestations. Download the workflow artifact, then verify each file with `gh attestation verify PATH --repo Slipcast-dev/translator-Koto --signer-workflow Slipcast-dev/translator-Koto/.github/workflows/build-artifacts.yml`. These attestations bind bytes to a GitHub workflow/source revision; they do not provide Apple Developer ID or notarization. Existing locally built alpha.13 assets have not been retroactively attested. The workflow is merged and its first alpha.14 tag build completed successfully. See Docs/validation/release-14.json for the verified source revision and artifact hashes.

`CFBundleShortVersionString` is numeric (0.1.0); `KotoReleaseChannel` stores alpha for the UI. Do not set `SWIFT_VERSION` to a compiler minor version: 6.0 denotes the language mode. Runtime model loading now uses an unlinked verified snapshot via inherited stdin; reserve temporary disk space equal to the model size in addition to installed weights. No named model copy is retained.
