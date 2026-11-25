[Русский](CHANGELOG.md) | **English**

# Changelog

## 3.0.0

Release: [v3.0.0](https://github.com/Slipcast-dev/translator-Koto/releases/tag/v3.0.0). Chrome 0.1.6.

- New: progress and finished parts of long translations (local and cloud engines); a live-translation badge showing the engine with Pause and Stop; configurable global shortcuts; import and export of exact phrases (JSON, CSV); page translation while scrolling in the extensions (up to 10 minutes, 400 fragments or 100,000 characters).
- Fixes: an unreadable phrase or memory file is kept as a backup before it is overwritten; after Stop, live translation sends no requests and a failed batch is not repeated line by line; text changes in large regions are detected; punctuation after a URL no longer rejects a translation; after errors live translation retries or pauses; display changes pause it.
- Robustness: a queue for local-model requests; runtime I/O moved off the Swift thread pool; the bridge keeps a connection open while translating; the native host answers `busy` instead of exiting; Remove translation, Cancel and a failed fragment stop extension requests; an update whose new version never starts is rolled back.
- Security: bridge rate limit (300 requests and 150,000 characters per minute); the ⌘C fallback can be turned off and waits longer for the copy; the test-only bridge directory variable is gone from the shipped host; DMG name validation; update-key rotation; releases require tests and use the `release` environment; cmake and ninja are hash-checked; signing with your own certificate pins permissions to its fingerprint.
- Performance: fewer captures of an unchanged screen; short page fragments are batched when the source language is explicit; the live cache evicts only old entries.

## 2.0.0

Release: [v2.0.0](https://github.com/Slipcast-dev/translator-Koto/releases/tag/v2.0.0).

- Security: the updater verifies an Ed25519 signature over `SHA256SUMS.txt`, accepts files only from this repository's releases and no longer strips quarantine; build and publish are separate jobs; developer launch flags are Debug-only; tokens and keys are removed on quit; the native host verifies the app signature.
- Reliability: cloud translation splits long text and retries on 429/5xx; one shared language list; disk writes use F_FULLFSYNC.
- Speed: Chrome 0.1.5 runs four requests in parallel; local model threads follow performance cores; resumable model download; batched translation-memory writes; ETag for update checks.
- Documentation: threat model in SECURITY.md, update signing key in BUILDING.md; a warning that translation memory is not encrypted.

## 1.0.1

Release: [v1.0.1](https://github.com/Slipcast-dev/translator-Koto/releases/tag/v1.0.1).

- In-place live translation, a “Word under the cursor” mode, the window hides after choosing the region (stop with ⌃⌥⌘L or the Koto menu).
- Main window: separate centred engine buttons, “Translate” and “Clear” under the input field.
- Language auto-detection works on short words; selected-text translation falls back to ⌘C with clipboard restore.
- Security: password managers excluded by default; large clipboards are never copied; the restore is marked as auto-generated.
- Speed: text recognition warm-up at launch, batched in-place translation, slower mouse polling outside the region, update image mount retried.
- README: stars and downloads badges.
- First stable release line (1.0.0): no alpha markers, signing is still ad hoc, without Developer ID or notarization.
