[Русский](PRIVACY.md) | **English**

# Data and permissions

Apple Translation, Vision and Qwen run on the device. Apple languages and Qwen may require separate downloads. Qwen is downloaded from a pinned Hugging Face URL only through an explicit button action.

Accessibility enables selection reading; Screen Capture enables reading the selected region. System category names and permission scope depend on macOS. Permissions are granted by the Mac owner; confirmations are never bypassed. Screenshots are not saved.

The browser bridge is disabled by default: it uses a private AF_UNIX socket, HELLO/token authentication and the extension's own origin. After a user action, the extension reads selections/visible fragments from the active HTTP(S) page, skips fields/code/editable content, and sends the origin without path/query. Original DOM text nodes are not replaced; translations are added separately and can be cleared with a button.

Cloud adapters use the selected provider and a Keychain-stored key; capture/browser/Live each require separate opt-in switches. There is no automatic fallback to cloud translation. Real provider accounts have not yet been validated.

Manual translation memory is off by default and holds at most 500 phrases; capture/browser/Live content is not stored. The exact-phrase glossary is a separate explicit setting. Diagnostic exports must not include keys or original texts.

The localized build uses neutral Ready/Translating statuses for cloud engines. The selected engine and cloud submission permissions remain visible; idle labels do not claim cloud processing happens on the device. [Status](STATUS.en.md).

## Updates and Safari

The update check runs at launch (at most once an hour; it can be turned off in Settings) and on demand; it contacts `api.github.com` and GitHub download hosts (HTTPS; redirects are limited to github.com and githubusercontent.com); translation text and keys are never sent. Nothing is downloaded until the user agrees. The downloaded DMG is checked against the same release's SHA256SUMS.txt; this protects against corruption in transit but is not publisher verification (ad hoc signature, and attestations are not verified in-app). The Safari extension runs sandboxed with narrow exceptions: reading the bridge token and connecting to Koto's bridge socket; the same token, origin and 0700 directory apply as for Chrome.

## Границы доверия / Trust boundaries

The public `manifest.key` fixes the ID of the unpacked extension; it is not a secret or proof of publisher identity. Another locally installed extension with the same key can use the same ID. The bridge also requires a 32-byte token stored in a 0700 user-owned directory with 0600 files. Native host checks the connected socket UID before sending HELLO. The app, which accepts connections through Network.framework, does not check the client UID and relies on the token, the extension origin, the 0700 directory and socket owner verification. Arbitrary malicious code running under the same UID can read user-owned files: this token does not establish isolation from that threat. Do not install untrusted unpacked extensions.

Default browser exclusions apply only when `privacy.excludedHosts` has not been set; an explicit user list, including an empty list, is respected. The initial list covers selected mail/payment/banking hosts and is not a complete list of sensitive sites. Customize it in Settings. Browser text and origin are captured in the same document; page insertions are bound to its documentId.

Long UTF-8 Application Support paths use a short user-owned 0700 socket directory under /tmp; the token remains in Application Support. Cloud HTTPS inherits system proxy/PAC and still rejects redirects. Keychain creation and update request the same WhenUnlockedThisDeviceOnly attribute. The legacy macOS backend may ignore it; strict accessibility/device-only guarantees require Data Protection Keychain and a suitable signing identity/entitlements. The preview is not App Sandbox isolated; TCC still controls Screen Capture/Accessibility. A sandboxed architecture requires separate compatibility design and testing, rather than toggling ENABLE_APP_SANDBOX without evidence. The model starts from an anonymous verified snapshot passed through stdin and /dev/fd/0; later changes to the source file do not affect the loaded bytes. On APFS the snapshot is an instant copy-on-write clone; otherwise a full temporary copy is made. No named copy is kept, and the runtime is unloaded after 10 minutes without requests.
