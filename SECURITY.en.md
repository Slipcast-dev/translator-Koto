[Русский](SECURITY.md) | **English**

# Security

Only the current release is supported; no SLA is promised. Relevant areas include text handling, Keychain, runtime/model integrity and native messaging.

Do not disclose secrets or private exploit details in a regular issue. Private Vulnerability Reporting is enabled: use [Report a vulnerability](https://github.com/Slipcast-dev/translator-Koto/security/advisories/new) to contact the maintainer privately. Reports in Russian and English are welcome. No email or PGP address is claimed.

A fix requires a minimal reproducer and verification without user data. Do not bypass Gatekeeper/TCC for testing.

## Threat model

- **The boundary is the user account.** The browser bridge is protected by a socket and a token (`bridge.token`, mode 0600, present only while the bridge is on). Any process of the same user can read the token and use the bridge, including supplying `pageOrigin` and bypassing the excluded-sites list. Koto does not defend against malicious code running as you; it does defend against other users and sandboxed processes.
- **Bridge limit.** At most 300 requests and 150,000 characters per minute across the app: this bounds cloud quota spent by anyone holding the token, but does not replace the account boundary.
- **Updates.** The app installs only a release whose `SHA256SUMS.txt` is signed with the developer's Ed25519 key (the public key is built into the app) and whose files come from this repository's releases. The app is ad hoc signed: there is no Developer ID or notarization yet, so Gatekeeper does not vouch for the publisher, and the updater does not strip quarantine.
- **Translation memory** (optional) is stored as plain JSON with mode 0600; cloud keys live in the Keychain.
- The main app runs without the App Sandbox (it needs screen capture, the local runtime and the bridge); the Safari extension is sandboxed.
