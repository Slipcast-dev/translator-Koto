import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Быстрый перевод коротких фрагментов с кэшем. Не показывает UI и не пишет текст на диск.
@MainActor
final class QuickTranslator {
    enum Outcome { case text(String), failure(String) }
    private let model = ManualTranslationModel(engine: RoutingTranslationEngine(), context: .live)
    private var cache: [String: String] = [:]

    var languageIDs: [String] { model.languages.map(\.id) }

    func cached(_ text: String, pair: (source: String, target: String)) -> String? {
        cache["\(pair.source)|\(pair.target)|\(text)"]
    }

    /// Несколько строк одним запросом: переводчик обычно сохраняет переносы. Если число строк в ответе не совпало,
    /// каждая строка переводится отдельно. Результаты кэшируются построчно.
    func translateBatch(_ texts: [String], pair: (source: String, target: String)) async -> [Outcome] {
        guard texts.count > 1 else {
            var single: [Outcome] = []
            for text in texts { single.append(await translate(text, pair: pair)) }
            return single
        }
        if case .text(let joined) = await translate(texts.joined(separator: "\n"), pair: pair) {
            let parts = joined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if parts.count == texts.count, parts.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                for (text, part) in zip(texts, parts) { cache["\(pair.source)|\(pair.target)|\(text)"] = part }
                return parts.map { .text($0) }
            }
        }
        var each: [Outcome] = []
        for text in texts { each.append(await translate(text, pair: pair)) }
        return each
    }

    func translate(_ text: String, pair: (source: String, target: String)) async -> Outcome {
        let key = "\(pair.source)|\(pair.target)|\(text)"
        if let cached = cache[key] { return .text(cached) }
        if model.languages.isEmpty { await model.loadLanguages() }
        for source in pair.source == "auto" ? ["auto", "en"] : [pair.source] {
            model.targetIdentifier = pair.target
            model.sourceIdentifier = source
            model.sourceText = text
            model.submit()
            while model.isBusy, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(30)) }
            if let result = model.result?.text, !result.isEmpty {
                if cache.count > 800 { cache.removeAll() }
                cache[key] = result
                return .text(result)
            }
            if model.phase == .needsDownload {
                return .failure(String(localized: "Language not downloaded. Prepare it in the main Koto window first."))
            }
            if model.failure != .unableToIdentify { break }
        }
        return .failure(model.failure?.errorDescription ?? String(localized: "Unable to translate."))
    }
}

struct OverlayLine: Identifiable, Equatable {
    let id: Int
    let frame: CGRect
    let text: String
    let background: [Double]
    let originalLength: Int
}

/// Прозрачная панель поверх выбранной области: перевод ложится на место исходной строки.
/// Панель не принимает мышь и не забирает фокус, поэтому приложение под ней работает как обычно.
@MainActor
final class InPlaceOverlay {
    private let panel: NSPanel
    private let hosting = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func show(lines: [OverlayLine], region: CGRect) {
        guard !lines.isEmpty else { hide(); return }
        hosting.rootView = AnyView(InPlaceOverlayView(lines: lines, region: region))
        panel.setFrame(region, display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

private struct InPlaceOverlayView: View {
    let lines: [OverlayLine]
    let region: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(lines) { line in
                let background = Color(red: line.background[0], green: line.background[1], blue: line.background[2])
                let luminance = 0.299 * line.background[0] + 0.587 * line.background[1] + 0.114 * line.background[2]
                // Перевод обычно длиннее оригинала: рамка растёт вправо до края области.
                let ratio = max(1, Double(line.text.count) / Double(max(1, line.originalLength)))
                let width = min(line.frame.width * min(ratio, 2.2) + 8, region.maxX - line.frame.minX)
                Text(line.text)
                    .font(.system(size: max(9, line.frame.height * 0.72), weight: .medium))
                    .foregroundStyle(luminance > 0.55 ? Color.black : Color.white)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(.horizontal, 3)
                    .frame(width: max(width, line.frame.width), height: line.frame.height + 2, alignment: .leading)
                    .background(background, in: RoundedRectangle(cornerRadius: 3))
                    .offset(x: line.frame.minX - region.minX - 1, y: region.maxY - line.frame.maxY - 1)
            }
        }
        .frame(width: region.width, height: region.height, alignment: .topLeading)
    }
}

/// Живой перевод на месте: Koto находит иностранный текст в области, определяет язык каждой строки
/// и показывает перевод поверх исходной строки. Кадр не меняется — OCR и перевод не повторяются.
@MainActor
final class InPlaceTranslationController {
    private let ocr: ScreenOCRService
    private let translator = QuickTranslator()
    private let overlay = InPlaceOverlay()
    private var loop: Task<Void, Never>?
    private var fingerprint: FrameFingerprint?

    init(ocr: ScreenOCRService) { self.ocr = ocr }

    func start(region: CGRect, screen: NSScreen, pair: @escaping () -> (source: String, target: String),
               onStatus: @escaping (String) -> Void) {
        stop()
        fingerprint = nil
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let frame = try await self.ocr.lines(in: region, screen: screen, previous: self.fingerprint)
                    guard !Task.isCancelled else { return }
                    self.fingerprint = frame.fingerprint
                    if let lines = frame.lines {
                        // Кадр изменился: старые подписи могут стоять не на месте.
                        self.overlay.hide()
                        await self.translate(lines, region: region, pair: pair(), onStatus: onStatus)
                    }
                } catch is CancellationError { return }
                catch CaptureFailure.noText { self.overlay.hide() }
                catch {
                    self.overlay.hide()
                    onStatus((error as? CaptureFailure)?.errorDescription ?? String(localized: "Live capture stopped after an error"))
                    return
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil; fingerprint = nil; overlay.hide() }

    private func translate(_ lines: [RecognizedLine], region: CGRect, pair: (source: String, target: String),
                           onStatus: (String) -> Void) async {
        if translator.languageIDs.isEmpty { _ = await translator.translate("a", pair: pair) }
        // Нужны только строки на другом языке; уже переведённые берутся из кэша мгновенно.
        var wanted: [(index: Int, line: RecognizedLine)] = []
        for (index, line) in lines.enumerated() {
            if pair.source == "auto" {
                guard let language = LanguageDetector.detect(line.text, among: translator.languageIDs),
                      language != pair.target else { continue }
            } else if pair.source == pair.target { continue }
            wanted.append((index, line))
        }
        var shown: [Int: OverlayLine] = [:]
        func publish() { overlay.show(lines: shown.keys.sorted().compactMap { shown[$0] }, region: region) }
        func add(_ item: (index: Int, line: RecognizedLine), _ text: String) {
            shown[item.index] = OverlayLine(id: item.index, frame: item.line.frame, text: text,
                                            background: item.line.background, originalLength: item.line.text.count)
        }
        var pending: [(index: Int, line: RecognizedLine)] = []
        for item in wanted {
            if let cached = translator.cached(item.line.text, pair: pair) { add(item, cached) } else { pending.append(item) }
        }
        if !shown.isEmpty { publish() }
        // Пачки до 12 строк и 1500 символов: меньше запросов, чем по одной строке.
        var start = 0
        while start < pending.count, !Task.isCancelled {
            var end = start, size = 0
            while end < pending.count, end - start < 12, size + pending[end].line.text.count <= 1500 || end == start {
                size += pending[end].line.text.count; end += 1
            }
            let chunk = Array(pending[start..<end])
            let results = await translator.translateBatch(chunk.map(\.line.text), pair: pair)
            guard !Task.isCancelled else { return }
            for (item, result) in zip(chunk, results) {
                switch result {
                case .text(let text): add(item, text)
                case .failure(let message): onStatus(message)
                }
            }
            publish()
            start = end
        }
    }
}
