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
