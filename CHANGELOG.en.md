[Русский](CHANGELOG.md) | **English**

# Changelog

## 1.0.1

Release: [Docs/RELEASE-1.0.1.md](Docs/RELEASE-1.0.1.md).

- In-place live translation, a “Word under the cursor” mode, the window hides after choosing the region (stop with ⌃⌥⌘L or the Koto menu).
- Main window: separate centred engine buttons, “Translate” and “Clear” under the input field.
- Language auto-detection works on short words; selected-text translation falls back to ⌘C with clipboard restore.
- Security: password managers excluded by default; large clipboards are never copied; the restore is marked as auto-generated.
- Speed: text recognition warm-up at launch, batched in-place translation, slower mouse polling outside the region, update image mount retried.
- README: stars and downloads badges.
- First stable release line (1.0.0): no alpha markers, signing is still ad hoc, without Developer ID or notarization.
