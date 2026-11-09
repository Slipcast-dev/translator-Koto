import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Подсказка с переводом рядом со словом. Не принимает мышь и не забирает фокус.
@MainActor
final class HoverTooltip {
    private let panel: NSPanel
    private let hosting = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func show(_ text: String, above frame: CGRect, on screen: CGRect) {
        hosting.rootView = AnyView(Text(text).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
            .lineLimit(3).multilineTextAlignment(.center).padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .fixedSize())
        let size = hosting.fittingSize
        var origin = CGPoint(x: frame.midX - size.width / 2, y: frame.maxY + 6)
        if origin.y + size.height > screen.maxY { origin.y = frame.minY - size.height - 6 }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    /// Перевод всей области: панель ложится поверх выбранного прямоугольника и пропускает мышь сквозь себя.
    func showCovering(_ text: String, frame: CGRect) {
        hosting.rootView = AnyView(ScrollView { Text(text).font(.system(size: 16, weight: .medium)).foregroundStyle(.primary)
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .topLeading).padding(12) }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

/// Перевод слова под курсором: пока указатель неподвижен в выбранной области, Koto читает слово
/// рядом с ним и показывает перевод подсказкой. Снимок маленький, на диск и в историю ничего не пишется.
@MainActor
final class HoverTranslationController {
    private let ocr: ScreenOCRService
    private let translator = ManualTranslationModel(engine: RoutingTranslationEngine(), context: .live)
    private let tooltip = HoverTooltip()
    private var loop: Task<Void, Never>?
    private var cache: [String: String] = [:]
    private var shownFrame: CGRect?

    init(ocr: ScreenOCRService) { self.ocr = ocr }

    var active: Bool { loop != nil }

    func start(region: CGRect, screen: NSScreen, pair: @escaping () -> (source: String, target: String),
               onStatus: @escaping (String) -> Void) {
        stop()
        loop = Task { [weak self] in
            var lastPoint = NSEvent.mouseLocation
            var stillSince = ContinuousClock.now
            var handled = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self else { return }
                let point = NSEvent.mouseLocation
                guard region.contains(point) else {
                    self.hide(); handled = true; lastPoint = point; continue
                }
                if hypot(point.x - lastPoint.x, point.y - lastPoint.y) > 3 {
                    lastPoint = point; stillSince = .now; handled = false
                    if let shown = self.shownFrame, !shown.insetBy(dx: -4, dy: -4).contains(point) { self.hide() }
                    continue
                }
                guard !handled, stillSince.duration(to: .now) >= .milliseconds(180) else { continue }
                handled = true
                do {
                    guard let word = try await self.ocr.word(at: point, within: region, screen: screen) else { self.hide(); continue }
                    // Курсор мог уйти, пока шёл OCR.
                    guard NSEvent.mouseLocation.distance(to: point) <= 6 else { continue }
                    let text = await self.translate(word.text, pair: pair())
                    guard NSEvent.mouseLocation.distance(to: point) <= 6 else { continue }
                    self.shownFrame = word.frame
                    self.tooltip.show(text, above: word.frame, on: screen.frame)
                } catch is CancellationError { return }
                catch {
                    self.hide()
                    onStatus((error as? CaptureFailure)?.errorDescription ?? (error as? TranslationFailure)?.errorDescription
                        ?? String(localized: "Live capture stopped after an error"))
                    if error is CaptureFailure { return }
                }
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil; hide() }

    private func hide() { shownFrame = nil; tooltip.hide() }

    /// Всегда возвращает текст подсказки: перевод или короткую причину, почему его нет.
    private func translate(_ word: String, pair: (source: String, target: String)) async -> String {
        let key = "\(pair.source)|\(pair.target)|\(word.lowercased())"
        if let cached = cache[key] { return cached }
        if translator.languages.isEmpty { await translator.loadLanguages() }
        for source in pair.source == "auto" ? ["auto", "en"] : [pair.source] {
            translator.targetIdentifier = pair.target
            translator.sourceIdentifier = source
            translator.sourceText = word
            translator.submit()
            while translator.isBusy, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(40)) }
            if let text = translator.result?.text, !text.isEmpty {
                if cache.count > 500 { cache.removeAll() }
                cache[key] = text
                return text
            }
            if translator.phase == .needsDownload {
                return String(localized: "Language not downloaded. Open Live translation to prepare it.")
            }
            if translator.failure != .unableToIdentify { break }
        }
        return translator.failure?.errorDescription ?? String(localized: "Unable to translate.")
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
