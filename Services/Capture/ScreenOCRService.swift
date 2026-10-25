import AppKit
@preconcurrency import ScreenCaptureKit
import Vision

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
    func withExclusiveCapture(_ operation: () async throws -> String) async throws -> String {
        while captureInFlight {
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
        captureInFlight = true
        defer { captureInFlight = false }
        let text = try await operation()
        try Task.checkCancellation()
        return text
    }

    private func capture(selection: CGRect, screen: NSScreen, excludeOwnWindows: Bool) async throws -> String {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureFailure.screenRequired }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw CaptureFailure.unavailable
        }
        let rect = try CaptureGeometry.sourceRect(selection: selection, screen: screen.frame)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        return try await Self.recognizeImage(image)
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
