import AppKit

/// Панели принадлежат одной операции. Выбор ограничен одним дисплеем, Esc закрывает все панели.
@MainActor
final class RegionSelector {
    private var panels: [NSPanel] = []
    private var completion: ((CGRect?, NSScreen?) -> Void)?

    func begin(completion: @escaping (CGRect?, NSScreen?) -> Void) {
        cancel()
        self.completion = completion
        for screen in NSScreen.screens {
            let panel = SelectorPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
            panel.setFrame(screen.frame, display: false)
            // Nonactivating panel получает Esc, не поднимая главное окно Koto поверх исходного контента.
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onSelection = { [weak self] rect in
                guard let self else { return }
                let global = rect.map { $0.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY) }
                finish(rect: global, screen: global == nil ? nil : screen)
            }
            panel.contentView = view
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        if let panel = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panels.first {
            panel.makeKey()
            panel.makeFirstResponder(panel.contentView)
        }
    }

    func cancel() { if completion != nil { finish(rect: nil, screen: nil) } }

    private func finish(rect: CGRect?, screen: NSScreen?) {
        let callback = completion
        completion = nil
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        callback?(rect, screen)
    }
}

private final class SelectorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class RegionSelectionView: NSView {
    var onSelection: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
            .standardized.intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let selection, selection.width >= 8, selection.height >= 8 else {
            onSelection?(nil)
            return
        }
        onSelection?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onSelection?(nil) } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.26).setFill()
        bounds.fill()
        if let selection {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 2
            border.stroke()
        }
        let hint = "Выделите область с текстом · Esc — отмена"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.white
        ]
        hint.draw(at: CGPoint(x: 28, y: bounds.height - 60), withAttributes: attributes)
    }
}
