[Русский](MODELS.md) | **English**

# Optional local model

Selected: **Qwen3 4B Instruct 2507 · Q4_K_M**, based on Qwen/Qwen3-4B-Instruct-2507, quantized by unsloth/Qwen3-4B-Instruct-2507-GGUF. Apache 2.0, minimum 8 GiB RAM.

- File: Qwen3-4B-Instruct-2507-Q4_K_M.gguf.
- Revision: `a06e946bb6b655725eafa393f4a9745d460374c9`.
- Size: 2,497,281,120 bytes.
- SHA-256: `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597`.

Catalog: Resources/LocalModels/manifest.json; lock: ThirdParty/model-lock.json. **Git, the app and the DMG contain no weights.** Installation starts only through the Settings button. HTTPS, size, GGUF format and SHA-256 are verified before atomic activation; cancellation and removal are supported. Downloading and verification require free space for approximately two copies plus temporary overhead.

Installed location: `~/Library/Application Support/dev.slipcast.koto/Models/qwen3-4b-instruct-2507-q4_k_m/`. The model stays outside the project; Apple Translation does not depend on it.

## Selection and quality

Across 16 main and 8 held-out examples, engineering review favored Instruct in 6 cases and the previous candidate in 2; both had material defects in 4, and 12 were similar. This is not independent linguistic certification or an accuracy percentage.

A 10,949-character / 40-paragraph document was processed in full, including its last sentence; approximately 224 seconds on M1 is an individual observation, not a controlled benchmark. Errors in idioms, explanations and language fragments remain. JSON/citation/URL checks do not guarantee semantic correctness. [Results](validation/results.json).
