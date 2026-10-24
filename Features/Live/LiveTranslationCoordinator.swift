import AppKit
import Observation

/// Producer последовательный: один screenshot/OCR. Новая строка отменяет старую модельную операцию.
/// ManualTranslationModel дополнительно защищает публикацию собственным request UUID.
@MainActor @Observable
final class LiveTranslationCoordinator {
    let model = ManualTranslationModel(engine: RoutingTranslationEngine(), context: .live)
    private(set) var running = false
    private(set) var paused = false
    private(set) var message = "Выберите область экрана для живого перевода"
    private(set) var captures = 0
    private(set) var translations = 0
    private(set) var latencyMilliseconds: [Double] = []
    @ObservationIgnored private let selector = RegionSelector()
    @ObservationIgnored private let ocr = ScreenOCRService()
    @ObservationIgnored private var gate = LiveFrameGate()
    @ObservationIgnored private var producer: Task<Void, Never>?
    @ObservationIgnored private var region: CGRect?
    @ObservationIgnored private var screenFrame: CGRect?
    @ObservationIgnored private var displayID: UInt32?
    @ObservationIgnored private var submittedAt: ContinuousClock.Instant?
    @ObservationIgnored private var countedID: UUID?

    var p50: Double? { percentile(0.50) }
    var p95: Double? { percentile(0.95) }
    var hasRegion: Bool { region != nil }
    var regionDescription: String {
        guard let region else { return "Область не выбрана" }
        return "\(Int(region.width)) × \(Int(region.height)) точек"
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
        }
    }

    func resume() {
        guard region != nil, !running else { return }
        let id = gate.reset()
        running = true; paused = false
        message = "Наблюдаем выбранную область · интервал не меньше 2 секунд"
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
                    let text = try await self.ocr.recognize(selection: region, screen: screen, excludeOwnWindows: true)
                    guard !Task.isCancelled, self.gate.generation == id else { return }
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
                    self.message = "В области пока нет текста"
                } catch is CancellationError { return }
                catch {
                    guard self.gate.generation == id else { return }
                    self.pause()
                    self.message = (error as? CaptureFailure)?.errorDescription ?? "Живой захват остановлен после ошибки"
                    return
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    func pause() {
        producer?.cancel(); producer = nil
        _ = gate.reset()
        model.cancel()
        running = false; paused = hasRegion
        message = "Живой перевод приостановлен"
    }

    func stop() {
        pause()
        selector.cancel()
        region = nil; screenFrame = nil; displayID = nil
        paused = false
        model.clear()
        message = "Живой перевод остановлен"
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
        message = "Движок изменён. Нажмите «Продолжить», чтобы возобновить захват."
    }

    func didPublish() {
        guard let result = model.result, result.requestID != countedID, let submittedAt else { return }
        countedID = result.requestID
        translations += 1
        let elapsed = submittedAt.duration(to: .now).components
        latencyMilliseconds.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        if latencyMilliseconds.count > 120 { latencyMilliseconds.removeFirst() }
        message = "Готово · повторный перевод запускается только при изменении текста"
    }

    private func percentile(_ fraction: Double) -> Double? {
        guard !latencyMilliseconds.isEmpty else { return nil }
        let sorted = latencyMilliseconds.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))]
    }
}
