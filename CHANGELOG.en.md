[Русский](CHANGELOG.md) | **English**

# Changelog

## 1.0.2

Release: [Docs/RELEASE-1.0.2.md](Docs/RELEASE-1.0.2.md).

- Security: the updater verifies an Ed25519 signature over `SHA256SUMS.txt`, accepts files only from this repository's releases and no longer strips quarantine; build and publish are separate jobs; developer launch flags are Debug-only; tokens and keys are removed on quit; the native host verifies the app signature.
- Reliability: cloud translation splits long text and retries on 429/5xx; one shared language list; disk writes use F_FULLFSYNC.
- Speed: Chrome 0.1.5 runs four requests in parallel; local model threads follow performance cores; resumable model download; batched translation-memory writes; ETag for update checks.
- Documentation: threat model in SECURITY.md, update signing key in BUILDING.md; a warning that translation memory is not encrypted.

## 1.0.1

Release: [Docs/RELEASE-1.0.1.md](Docs/RELEASE-1.0.1.md).

- In-place live translation, a “Word under the cursor” mode, the window hides after choosing the region (stop with ⌃⌥⌘L or the Koto menu).
- Main window: separate centred engine buttons, “Translate” and “Clear” under the input field.
- Language auto-detection works on short words; selected-text translation falls back to ⌘C with clipboard restore.
- Security: password managers excluded by default; large clipboards are never copied; the restore is marked as auto-generated.
- Speed: text recognition warm-up at launch, batched in-place translation, slower mouse polling outside the region, update image mount retried.
- README: stars and downloads badges.
- First stable release line (1.0.0): no alpha markers, signing is still ad hoc, without Developer ID or notarization.
