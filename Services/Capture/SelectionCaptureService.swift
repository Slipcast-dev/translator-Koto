import AppKit
import ApplicationServices

/// Сервис читает только выделение focused element; полный value поля никогда не запрашивается.
@MainActor
final class SelectionCaptureService {
    func capture(application: NSRunningApplication) async throws -> CapturedText {
        guard AXIsProcessTrusted() else { throw CaptureFailure.accessibilityRequired }
        guard !application.isTerminated, application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw CaptureFailure.noApplication
        }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        // Чужое зависшее приложение не должно навсегда блокировать Koto.
        AXUIElementSetMessagingTimeout(app, 0.6)
        guard let element = attribute(app, kAXFocusedUIElementAttribute) else {
            throw CaptureFailure.noSelection
        }
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { throw CaptureFailure.noSelection }
        let focused = unsafeDowncast(element, to: AXUIElement.self)
        let role = attribute(focused, kAXSubroleAttribute) as? String
        guard role != kAXSecureTextFieldSubrole as String else { throw CaptureFailure.secureField }
        let anchor = selectionBounds(focused) ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        if let text = attribute(focused, kAXSelectedTextAttribute) as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try checked(text: text, anchor: anchor)
        }
        // Некоторые приложения предоставляют строку только для AX-диапазона.
        // Читаем именно выбранный диапазон, не полный value документа.
        if let range = attribute(focused, kAXSelectedTextRangeAttribute) {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                focused, kAXStringForRangeParameterizedAttribute as CFString, range, &value
            ) == .success, let text = value as? String, !text.isEmpty {
                return try checked(text: text, anchor: anchor)
            }
        }
        throw CaptureFailure.noSelection
    }

    private func checked(text: String, anchor: CGRect) throws -> CapturedText {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CaptureFailure.noSelection }
        guard text.count <= TranslationRequest.characterLimit else { throw CaptureFailure.tooLong }
        return CapturedText(text: text, anchor: anchor)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func selectionBounds(_ element: AXUIElement) -> CGRect? {
        guard let range = attribute(element, kAXSelectedTextRangeAttribute) else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &raw
        ) == .success, let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        let value = unsafeDowncast(raw, to: AXValue.self)
        guard AXValueGetValue(value, .cgRect, &rect), !rect.isEmpty else { return nil }
        return CaptureGeometry.appKitRect(fromAX: rect, primaryHeight: NSScreen.screens.first?.frame.maxY ?? 0)
    }

}
