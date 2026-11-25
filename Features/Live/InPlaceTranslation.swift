import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

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

/// Паузы повтора после ошибок и интервал опроса неизменного экрана.
enum LiveSchedule {
    /// Первые неизменные кадры проверяются часто; на статичном экране интервал растёт до 1,5 с.
    nonisolated static func idleInterval(unchanged: Int) -> Duration {
        .milliseconds(min(1_500, 600 + max(0, unchanged - 5) * 150))
    }
    /// 2, 4, 8, 16, затем 30 секунд.
    nonisolated static func retryDelay(failures: Int) -> Duration {
        .seconds(min(30, 1 << min(5, max(1, failures))))
    }
    /// Столько сбоев захвата подряд считаются устойчивыми: режим переходит в паузу.
    nonisolated static let captureFailureLimit = 5
}

/// Живой перевод на месте: Koto находит иностранный текст в области, определяет язык каждой строки
/// и показывает перевод поверх исходной строки. Кадр не меняется — OCR и перевод не повторяются.
@MainActor
final class InPlaceTranslationController {
    private let ocr: ScreenOCRService
    private let translator = QuickTranslator(engine: RoutingTranslationEngine())
    private let overlay = InPlaceOverlay()
    private var loop: Task<Void, Never>?
    private var fingerprint: FrameFingerprint?

    init(ocr: ScreenOCRService) { self.ocr = ocr }

    /// `onFailure` сообщает, что цикл завершён: владелец обязан показать паузу, а не «работает».
    func start(region: CGRect, screen: NSScreen, pair: @escaping () -> (source: String, target: String),
               onStatus: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
        stop()
        fingerprint = nil
        loop = Task { [weak self] in
            var unchanged = 0, captureFailures = 0, translationFailures = 0
            var lastLines: [RecognizedLine]?
            var retryAt: ContinuousClock.Instant?
            while !Task.isCancelled {
                guard let self else { return }
                var pause = LiveSchedule.idleInterval(unchanged: unchanged)
                do {
                    // Срок повтора наступил: тот же кадр распознаётся и переводится снова.
                    if let due = retryAt, ContinuousClock.now >= due { self.fingerprint = nil; retryAt = nil }
                    let frame = try await self.ocr.lines(in: region, screen: screen, previous: self.fingerprint)
                    guard !Task.isCancelled else { return }
                    captureFailures = 0
                    self.fingerprint = frame.fingerprint
                    if let lines = frame.lines {
                        unchanged = 0
                        // Прежние подписи остаются, пока строки те же: это убирает мигание поверх видео.
                        if lines != lastLines { self.overlay.hide() }
                        lastLines = lines
                        let complete = await self.translate(lines, region: region, pair: pair(), onStatus: onStatus)
                        guard !Task.isCancelled else { return }
                        if complete { translationFailures = 0; retryAt = nil }
                        else {
                            translationFailures += 1
                            retryAt = .now.advanced(by: LiveSchedule.retryDelay(failures: translationFailures))
                        }
                        pause = LiveSchedule.idleInterval(unchanged: 0)
                    } else { unchanged += 1 }
                } catch is CancellationError { return }
                catch CaptureFailure.noText { self.overlay.hide(); lastLines = nil }
                catch {
                    self.overlay.hide()
                    lastLines = nil
                    self.fingerprint = nil
                    captureFailures += 1
                    let message = (error as? CaptureFailure)?.errorDescription ?? String(localized: "Live capture stopped after an error")
                    // Отсутствие доступа повтором не исправить; остальные сбои (сон дисплея) временные.
                    if (error as? CaptureFailure) == .screenRequired || captureFailures >= LiveSchedule.captureFailureLimit {
                        onFailure(message)
                        return
                    }
                    onStatus(message)
                    pause = LiveSchedule.retryDelay(failures: captureFailures)
                }
                try? await Task.sleep(for: pause)
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil; translator.cancel(); fingerprint = nil; overlay.hide() }

    func resetTranslator() { translator.reset() }

    /// false — часть строк не переведена и кадр нужно повторить позже.
    private func translate(_ lines: [RecognizedLine], region: CGRect, pair: (source: String, target: String),
                           onStatus: (String) -> Void) async -> Bool {
        await translator.loadLanguages()
        guard !Task.isCancelled else { return false }
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
            guard !Task.isCancelled else { return false }
            var failed: String?
            for (item, result) in zip(chunk, results) {
                switch result {
                case .text(let text): add(item, text)
                case .failure(let message): failed = message
                case .cancelled: return false
                }
            }
            publish()
            // После отказа движка остальные пачки не отправляются: кадр повторится с паузой.
            if let failed { onStatus(failed); return false }
            start = end
        }
        return !Task.isCancelled
    }
}
