[Русский](CHANGELOG.md) | **English**

# Changelog

## 1.0.0

Release: [Docs/RELEASE-1.0.0.md](Docs/RELEASE-1.0.0.md).

- In-place live translation: Koto finds foreign text in the chosen region, detects each line’s language and draws the translation over the original line; the “Word under the cursor” mode shows a tooltip next to the word. The Koto window hides after choosing the region; stop with ⌃⌥⌘L again or from the Koto menu. Test builds are signed by identifier, so granted permissions survive a rebuild (grant them again once or press “Reset and ask again”).
- First stable release: no alpha markers, tag `v1.0.0`, file `Koto-1.0.0-20-arm64.dmg`. Signing is still ad hoc, without Developer ID or notarization.
- Selected-text translation also works where an app does not expose the selection through Accessibility: Koto briefly copies the selection (⌘C) and restores the previous clipboard contents. Password fields are never read.
- Screen region: the translation window appears immediately with a progress indicator, and a denied Screen Recording shows the permissions panel instead of nothing.
- Language auto-detection works on short words (“привет” no longer fails); extra labels removed from the main window; Live mode buttons show full names.
- Main window: engine buttons are separate and centred, “Translate” and “Clear” sit under the input field, the title is gone from the toolbar.
- Settings simplified: tabs General, Translation, Privacy, Browsers, Advanced; permissions are two rows with an “Allow…” button.
