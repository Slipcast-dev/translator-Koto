import AppKit

/// macOS передаёт выделение службе через отдельный pasteboard. General не читается и не меняется.
/// Это резервный путь для приложений без AXSelectedText, без неоднозначной эмуляции Cmd+C.
@MainActor
final class CaptureServiceProvider: NSObject {
    var receive: ((String) -> Void)?

    @objc func translateSelection(
        _ pasteboard: NSPasteboard, userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pasteboard.string(forType: .string)
                ?? pasteboard.string(forType: NSPasteboard.PasteboardType("NSStringPboardType")),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = CaptureFailure.noSelection.errorDescription as NSString?
            return
        }
        guard text.count <= TranslationRequest.characterLimit else {
            error.pointee = CaptureFailure.tooLong.errorDescription as NSString?
            return
        }
        guard let receive else {
            error.pointee = CaptureFailure.unavailable.errorDescription as NSString?
            return
        }
        receive(text)
    }
}
