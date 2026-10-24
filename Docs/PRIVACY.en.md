[Русский](PRIVACY.md) | **English**

# Data and permissions

Apple Translation, Vision and Qwen run on the device. Apple languages and Qwen may require separate downloads. Qwen is downloaded from a pinned Hugging Face URL only through an explicit button action.

Accessibility enables selection reading; Screen Capture enables reading the selected region. System category names and permission scope depend on macOS. Permissions are granted by the Mac owner; confirmations are never bypassed. Screenshots are not saved.

The browser bridge is disabled by default: it uses a private AF_UNIX socket, HELLO/token authentication and the extension's own origin. After a user action, the extension reads selections/visible fragments from the active HTTP(S) page, skips fields/code/editable content, and sends the origin without path/query. Original DOM text nodes are not replaced; translations are added separately and can be cleared with a button.

Cloud adapters use the selected provider and a Keychain-stored key; capture/browser/Live each require separate opt-in switches. There is no automatic fallback to cloud translation. Real provider accounts have not yet been validated.

Manual translation memory is off by default and holds at most 500 phrases; capture/browser/Live content is not stored. The exact-phrase glossary is a separate explicit setting. Diagnostic exports must not include keys or original texts.

Known alpha defect: a cloud engine's idle status may incorrectly say On device (На устройстве). Check the selected engine and submission permissions; this defect has not been declared fixed. [Status](STATUS.en.md).
