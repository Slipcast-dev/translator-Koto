import AppKit
import ApplicationServices

/// Читает выделенный текст другого приложения. Порядок способов от самого безопасного к запасному:
/// 1) Accessibility (выбранный текст сфокусированного элемента и выбранный диапазон);
/// 2) временное копирование Cmd+C с восстановлением буфера обмена, если приложение не отдаёт выделение
///    через Accessibility (многие браузеры, Electron, редакторы). Полное значение поля никогда не запрашивается.
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
        // Chromium и Electron строят дерево доступности только по запросу этого атрибута.
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        // Сфокусированный элемент приложения и системный: у части приложений доступен только один из них.
        var elements: [AXUIElement] = []
        for source in [app, AXUIElementCreateSystemWide()] {
            if let element = attribute(source, kAXFocusedUIElementAttribute),
               CFGetTypeID(element) == AXUIElementGetTypeID() {
                elements.append(unsafeDowncast(element, to: AXUIElement.self))
            }
        }
        for element in elements {
            let role = attribute(element, kAXSubroleAttribute) as? String
            guard role != kAXSecureTextFieldSubrole as String else { throw CaptureFailure.secureField }
        }
        for element in elements {
            if let text = selectedText(of: element) {
                return try checked(text: text, anchor: selectionBounds(element) ?? mouseAnchor())
            }
        }
        // Запасной способ: приложение не отдаёт выделение через Accessibility.
        if let text = await copiedSelection(from: application) {
            return try checked(text: text, anchor: elements.lazy.compactMap { self.selectionBounds($0) }.first ?? mouseAnchor())
        }
        throw CaptureFailure.noSelection
    }

    private func selectedText(of element: AXUIElement) -> String? {
        if let text = attribute(element, kAXSelectedTextAttribute) as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        // Некоторые приложения дают строку только для выбранного AX-диапазона.
        if let range = attribute(element, kAXSelectedTextRangeAttribute) {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, range, &value
            ) == .success, let text = value as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        return nil
    }

    /// Отправляет Cmd+C приложению, ждёт изменения буфера и сразу восстанавливает прежнее содержимое.
    /// Текст читается из буфера один раз и нигде не сохраняется; если выделения нет, буфер не меняется.
    private static let clipboardLimit = 8_000_000

    private func copiedSelection(from application: NSRunningApplication) async -> String? {
        let pasteboard = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        // Большое содержимое (изображения, файлы) в памяти не держим: без возможности вернуть его Cmd+C не отправляется.
        let savedBytes = saved.reduce(0) { $0 + $1.reduce(0) { $0 + $1.1.count } }
        guard savedBytes <= Self.clipboardLimit else { return nil }
        let before = pasteboard.changeCount
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return nil }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(application.processIdentifier)
        up.postToPid(application.processIdentifier)
        var copied: String?
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(40))
            if pasteboard.changeCount != before { copied = pasteboard.string(forType: .string); break }
        }
        if pasteboard.changeCount != before {
            pasteboard.clearContents()
            let restored = saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                // Менеджеры буфера обмена не должны записывать возврат прежнего содержимого как новую копию.
                item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
                return item
            }
            if !restored.isEmpty { pasteboard.writeObjects(restored) }
        }
        return copied
    }

    private func mouseAnchor() -> CGRect { CGRect(origin: NSEvent.mouseLocation, size: .zero) }

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
