import AppKit
@preconcurrency import ScreenCaptureKit
import Vision

/// Грубый отпечаток кадра: уменьшенное серое изображение. Хранится только последний, на диск не пишется.
struct FrameFingerprint: Sendable {
    fileprivate let samples: [UInt8]
    nonisolated static let side = 48
    /// Средняя разница яркости (0...255), ниже которой кадр считается тем же: шум сжатия и мигание курсора.
    nonisolated static let tolerance = 2.0
    func matches(_ other: FrameFingerprint) -> Bool {
        guard samples.count == other.samples.count, !samples.isEmpty else { return false }
        let total = zip(samples, other.samples).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(samples.count) <= Self.tolerance
    }
    nonisolated static func make(from image: CGImage) -> FrameFingerprint? {
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? FrameFingerprint(samples: pixels) : nil
    }
}

/// Одно изображение только выбранного прямоугольника; нет потока кадров и записи на диск.
@MainActor
final class ScreenOCRService {
    private var captureInFlight = false
    func recognize(selection: CGRect, screen: NSScreen, excludeOwnWindows: Bool = false) async throws -> String {
        try await withExclusiveCapture {
            try await capture(selection: selection, screen: screen, excludeOwnWindows: excludeOwnWindows)
        }
    }

    /// Отменённый producer может всё ещё ждать Vision. Resume ждёт освобождения
    /// ресурса, не создавая второй OCR и не превращая временную занятость в ошибку.
    func withExclusiveCapture<T>(_ operation: () async throws -> T) async throws -> T {
        while captureInFlight {
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
        captureInFlight = true
        defer { captureInFlight = false }
        let value = try await operation()
        try Task.checkCancellation()
        return value
    }

    /// Для Live: если кадр визуально не изменился, дорогой Vision не запускается (text == nil).
    /// Сравнение с предыдущим отпечатком выполняется по тому же снимку, который иначе пошёл бы в OCR.
    func recognizeIfChanged(selection: CGRect, screen: NSScreen, excludeOwnWindows: Bool = false,
                            previous: FrameFingerprint?) async throws -> (text: String?, fingerprint: FrameFingerprint?) {
        try await withExclusiveCapture {
            let image = try await captureImage(selection: selection, screen: screen, excludeOwnWindows: excludeOwnWindows)
            let current = FrameFingerprint.make(from: image)
            if let previous, let current, current.matches(previous) { return (nil, previous) }
            return (try await Self.recognizeImage(image), current)
        }
    }

    private func capture(selection: CGRect, screen: NSScreen, excludeOwnWindows: Bool) async throws -> String {
        try await Self.recognizeImage(captureImage(selection: selection, screen: screen, excludeOwnWindows: excludeOwnWindows))
    }

    func captureSnapshot(selection: CGRect, screen: NSScreen) async throws -> CGImage {
        try await captureImage(selection: selection, screen: screen, excludeOwnWindows: true)
    }

    private func captureImage(selection: CGRect, screen: NSScreen, excludeOwnWindows: Bool) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureFailure.screenRequired }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw CaptureFailure.unavailable
        }
        let rect = try CaptureGeometry.sourceRect(selection: selection, screen: screen.frame)
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { throw Self.mapped(error) }
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
            throw CaptureFailure.unavailable
        }
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        let scale = screen.backingScaleFactor
        config.width = max(1, Int((rect.width * scale).rounded()))
        config.height = max(1, Int((rect.height * scale).rounded()))
        // Ограничиваем память и стоимость Vision на очень больших/Retina дисплеях.
        let ratio = min(1, 4096 / Double(max(config.width, config.height)))
        config.width = max(1, Int(Double(config.width) * ratio))
        config.height = max(1, Int(Double(config.height) * ratio))
        config.showsCursor = false
        config.captureResolution = .best
        let excluded = content.windows.filter {
            (excludeOwnWindows && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier)
                || TranslationPrivacy.excluded($0.owningApplication?.bundleIdentifier)
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let image: CGImage
        do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
        catch { throw Self.mapped(error) }
        try Task.checkCancellation()
        return image
    }

    /// Preflight может сообщать «доступ есть», а ScreenCaptureKit отказывает (устаревшая запись в списке разрешений).
    /// Такой отказ — вопрос разрешения, а не сбой захвата: пользователь увидит панель доступа.
    nonisolated static func mapped(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain", ns.code == -3801 { return CaptureFailure.screenRequired }
        return error
    }

    /// Синхронный Vision выполняется вне MainActor: перетаскивание/отмена остаются отзывчивыми.
    nonisolated static func recognizeImage(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            try Task.checkCancellation()
            let observations = request.results ?? []
            // Vision даёт normalized bottom-left координаты: группируем строки сверху вниз,
            // сохраняя чтение слева направо внутри близкой строки.
            let byHeight = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            var rows: [[VNRecognizedTextObservation]] = []
            for observation in byHeight {
                if let previous = rows.last?.first,
                   abs(previous.boundingBox.midY - observation.boundingBox.midY)
                       <= min(previous.boundingBox.height, observation.boundingBox.height) * 0.5 {
                    rows[rows.count - 1].append(observation)
                } else {
                    rows.append([observation])
                }
            }
            // Строгая сортировка внутри строки избегает нетранзитивного comparator с epsilon.
            let ordered = rows.flatMap { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
            let text = ordered.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CaptureFailure.noText }
            guard text.count <= TranslationRequest.characterLimit else { throw CaptureFailure.tooLong }
            return text
        }.value
    }
}

/// Слово на экране и его рамка в глобальных координатах AppKit.
struct RecognizedWord: Sendable, Equatable {
    let text: String
    let frame: CGRect
}

extension ScreenOCRService {
    /// Слово под указателем. Снимается только небольшой прямоугольник вокруг точки внутри выбранной области.
    func word(at point: CGPoint, within region: CGRect, screen: NSScreen) async throws -> RecognizedWord? {
        let window = CGRect(x: point.x - 180, y: point.y - 40, width: 360, height: 80)
            .intersection(region).intersection(screen.frame)
        guard !window.isNull, window.width >= 16, window.height >= 16 else { return nil }
        return try await withExclusiveCapture {
            let image = try await captureSnapshot(selection: window, screen: screen)
            let words = try await Self.recognizeWords(in: image, rect: window)
            return Self.nearest(words, to: point)
        }
    }

    nonisolated static func nearest(_ words: [RecognizedWord], to point: CGPoint) -> RecognizedWord? {
        func distance(_ word: RecognizedWord) -> CGFloat {
            let dx = max(word.frame.minX - point.x, 0, point.x - word.frame.maxX)
            let dy = max(word.frame.minY - point.y, 0, point.y - word.frame.maxY)
            return hypot(dx, dy)
        }
        guard let best = words.min(by: { distance($0) < distance($1) }), distance(best) <= 10 else { return nil }
        return best
    }

    nonisolated static func recognizeWords(in image: CGImage, rect: CGRect) async throws -> [RecognizedWord] {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            var words: [RecognizedWord] = []
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let string = candidate.string
                string.enumerateSubstrings(in: string.startIndex..<string.endIndex, options: .byWords) { substring, range, _, _ in
                    guard let substring, !substring.isEmpty, let box = try? candidate.boundingBox(for: range)?.boundingBox else { return }
                    let frame = CGRect(x: rect.minX + box.minX * rect.width, y: rect.minY + box.minY * rect.height,
                                       width: box.width * rect.width, height: box.height * rect.height)
                    words.append(RecognizedWord(text: substring, frame: frame))
                }
            }
            return words
        }.value
    }
}
