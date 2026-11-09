import AppKit
import Observation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Producer последовательный: один screenshot/OCR. Новая строка отменяет старую модельную операцию.
/// ManualTranslationModel дополнительно защищает публикацию собственным request UUID.
@MainActor @Observable
final class LiveTranslationCoordinator {
    let model = ManualTranslationModel(engine: RoutingTranslationEngine(), context: .live)
    /// Режим работы: слово под курсором (по умолчанию) или перевод всего текста области.
    enum Mode: String, CaseIterable, Identifiable { case hover, area; var id: String { rawValue } }
    var mode: Mode = .hover { didSet { if mode != oldValue, hasRegion { restart() } } }
    private(set) var running = false
    private(set) var paused = false
    private(set) var message = String(localized: "Choose a screen region for live translation")
    private(set) var captures = 0
    private(set) var translations = 0
    private(set) var latencyMilliseconds: [Double] = []
    @ObservationIgnored private let selector = RegionSelector()
    @ObservationIgnored private let ocr = ScreenOCRService()
    @ObservationIgnored private let overlay = HoverTooltip()
    /// Окно Koto не нужно, пока перевод виден поверх чужого приложения: View прячет его при запуске.
    @ObservationIgnored var onStarted: (() -> Void)?
    @ObservationIgnored private lazy var hover = HoverTranslationController(ocr: ocr)
    @ObservationIgnored private var gate = LiveFrameGate()
    @ObservationIgnored private var producer: Task<Void, Never>?
    @ObservationIgnored private var region: CGRect?
    @ObservationIgnored private var screenFrame: CGRect?
    @ObservationIgnored private var displayID: UInt32?
    @ObservationIgnored private var submittedAt: ContinuousClock.Instant?
    @ObservationIgnored private var fingerprint: FrameFingerprint?
    @ObservationIgnored private var countedID: UUID?

    var p50: Double? { percentile(0.50) }
    var p95: Double? { percentile(0.95) }
    var hasRegion: Bool { region != nil }
    var regionDescription: String {
        guard let region else { return String(localized: "No region selected") }
        return String(localized: "\(AppLocalization.number(Int(region.width))) × \(AppLocalization.number(Int(region.height))) points")
    }

    func chooseRegion() {
        stop()
        guard CGPreflightScreenCaptureAccess() else { message = CaptureFailure.screenRequired.errorDescription ?? ""; return }
        selector.begin { [weak self] rect, screen in
            guard let self, let rect, let screen,
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
            self.region = rect
            self.screenFrame = screen.frame
            self.displayID = number.uint32Value
            self.captures = 0; self.translations = 0; self.latencyMilliseconds.removeAll()
            self.resume()
            if self.running { self.onStarted?() }
        }
    }

    private func restart() { pause(); resume() }

    func resume() {
        guard let region, !running else { return }
        if mode == .hover {
            guard let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
            }), screen.frame == screenFrame else { message = CaptureFailure.invalidRegion.errorDescription ?? ""; return }
            running = true; paused = false
            message = String(localized: "Point the cursor at a word in the region: the translation appears next to it.")
            hover.start(region: region, screen: screen, pair: { [weak self] in
                (self?.model.sourceIdentifier ?? "auto", self?.model.targetIdentifier ?? "ru")
            }, onStatus: { [weak self] in self?.message = $0 })
            if model.languages.isEmpty { Task { await model.loadLanguages() } }
            return
        }
        let id = gate.reset()
        // Первый кадр после запуска или смены пары всегда проходит OCR.
        fingerprint = nil
        running = true; paused = false
        message = String(localized: "Watching the selected region · minimum interval: 2 seconds")
        producer = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.running, self.gate.generation == id {
                do {
                    guard let region = self.region, let originalScreen = self.screenFrame,
                          let screen = NSScreen.screens.first(where: {
                              ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == self.displayID
                          }), screen.frame == originalScreen, screen.frame.contains(region) else {
                        throw CaptureFailure.invalidRegion
                    }
                    let frame = try await self.ocr.recognizeIfChanged(selection: region, screen: screen, excludeOwnWindows: true,
                                                                      previous: self.fingerprint)
                    guard !Task.isCancelled, self.gate.generation == id else { return }
                    self.fingerprint = frame.fingerprint
                    // Кадр не изменился: OCR пропущен, состояние и перевод остаются прежними.
                    guard let text = frame.text else {
                        try await Task.sleep(for: .seconds(2))
                        continue
                    }
                    self.captures += 1
                    if self.gate.accept(text, generation: id) {
                        self.model.sourceText = text
                        if self.model.languages.isEmpty { await self.model.loadLanguages() }
                        guard !Task.isCancelled, self.gate.generation == id else { return }
                        self.submittedAt = .now
                        self.model.submit()
                    }
                } catch CaptureFailure.noText {
                    guard self.gate.generation == id else { return }
                    _ = self.gate.accept("", generation: id)
                    self.model.clear()
                    self.overlay.hide()
                    self.message = String(localized: "No text in the region yet")
                } catch is CancellationError { return }
                catch {
                    guard self.gate.generation == id else { return }
                    self.pause()
                    self.message = (error as? CaptureFailure)?.errorDescription ?? String(localized: "Live capture stopped after an error")
                    return
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    func pause() {
        hover.stop()
        overlay.hide()
        producer?.cancel(); producer = nil
        _ = gate.reset()
        model.cancel()
        running = false; paused = hasRegion
        message = String(localized: "Live translation paused")
    }

    func stop() {
        pause()
        selector.cancel()
        region = nil; screenFrame = nil; displayID = nil
        paused = false
        model.clear()
        message = String(localized: "Live translation stopped")
    }

    /// Смена пары должна повторно перевести даже неизменившийся кадр.
    func translationOptionsChanged() {
        let restart = running
        pause()
        model.clear()
        if restart { resume() }
    }

    func engineChanged() {
        pause()
        model.clear()
        Task { await model.loadLanguages() }
        message = String(localized: "The engine changed. Click Resume to continue capturing.")
    }

    func didPublish() {
        guard let result = model.result, result.requestID != countedID, let submittedAt else { return }
        countedID = result.requestID
        translations += 1
        let elapsed = submittedAt.duration(to: .now).components
        latencyMilliseconds.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        if latencyMilliseconds.count > 120 { latencyMilliseconds.removeFirst() }
        message = String(localized: "Ready · translation runs again only when the text changes")
        if mode == .area, let region { overlay.showCovering(result.text, frame: region) }
    }

    private func percentile(_ fraction: Double) -> Double? {
        guard !latencyMilliseconds.isEmpty else { return nil }
        let sorted = latencyMilliseconds.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))]
    }
}
