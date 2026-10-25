#!/bin/bash
# Воспроизводимая сборка официального llama.cpp: точный commit и локальные инструменты.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="7894e8b92481a8bb8ffe94f73b656ffe0dd01e10"
SOURCE_DIR="$ROOT_DIR/ThirdParty/llama.cpp"
CMAKE="$ROOT_DIR/build/tooling/bin/cmake"
NINJA="$ROOT_DIR/build/tooling/bin/ninja"
if [[ ! -x "$CMAKE" || ! -x "$NINJA" ]]; then
    python3 -m venv "$ROOT_DIR/build/tooling"
    "$ROOT_DIR/build/tooling/bin/python" -m pip install 'cmake==3.31.6' 'ninja==1.11.1.4'
fi
if [[ ! -f "$SOURCE_DIR/CMakeLists.txt" ]]; then
    git clone --no-checkout https://github.com/ggml-org/llama.cpp.git "$SOURCE_DIR"
    git -C "$SOURCE_DIR" checkout --detach "$PIN"
fi
if [[ -d "$SOURCE_DIR/.git" ]]; then
[[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" == "$PIN" ]] || {
    echo "llama.cpp source commit differs from the reviewed pin." >&2; exit 1;
}
fi
python3 "$ROOT_DIR/script/verify_runtime_source.py"
# Статическая линковка и embedded Metal исключают зависимость от Homebrew на Mac пользователя.
# UI/HTTPS отключены: runtime получает локальный файл и запросы Koto по приватному AF_UNIX.
"$CMAKE" -S "$SOURCE_DIR" -B "$ROOT_DIR/build/llama" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$NINJA" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=ON \
    -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_UI=OFF \
    -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_OPENSSL=OFF
"$CMAKE" --build "$ROOT_DIR/build/llama" --target llama-server --parallel 2
mkdir -p "$ROOT_DIR/Resources/LocalRuntime"
cp "$ROOT_DIR/build/llama/bin/llama-server" "$ROOT_DIR/Resources/LocalRuntime/llama-server"
cp "$SOURCE_DIR/LICENSE" "$ROOT_DIR/Resources/LocalRuntime/LLAMA-LICENSE.txt"
# Development-подпись вложенного executable не заменяет финальную identity Slipcast-Dev.
codesign --force --sign - "$ROOT_DIR/Resources/LocalRuntime/llama-server"
shasum -a 256 "$ROOT_DIR/Resources/LocalRuntime/llama-server"

xcrun clang++ -std=c++20 -O2 -arch arm64 -mmacosx-version-min=26.0 \
    "$ROOT_DIR/NativeTools/RuntimeLauncher.cpp" -o "$ROOT_DIR/Resources/LocalRuntime/koto-runtime-launcher"
codesign --force --sign - "$ROOT_DIR/Resources/LocalRuntime/koto-runtime-launcher"
cp -R "$SOURCE_DIR/licenses" "$ROOT_DIR/Resources/LocalRuntime/licenses"
python3 -c 'import pathlib,hashlib,json,sys; r=pathlib.Path(sys.argv[1]); value={"commit":"7894e8b92481a8bb8ffe94f73b656ffe0dd01e10","runtimeSHA256":hashlib.sha256((r/"llama-server").read_bytes()).hexdigest(),"launcherSHA256":hashlib.sha256((r/"koto-runtime-launcher").read_bytes()).hexdigest()}; (r/"manifest.json").write_text(json.dumps(value,indent=2)+"\n"); print(json.dumps(value))' "$ROOT_DIR/Resources/LocalRuntime"
