import AppKit
import Observation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Живой перевод поверх чужого приложения. Режимы: «На месте» (перевод ложится на исходные строки)
/// и «Слово под курсором» (подсказка рядом со словом). Окно Koto нужно только для настройки.
@MainActor @Observable
final class LiveTranslationCoordinator {
    enum Mode: String, CaseIterable, Identifiable { case inPlace, hover; var id: String { rawValue } }

    /// Модель хранит только выбор языков и каталог; сам перевод делают контроллеры режимов.
    let model = ManualTranslationModel(engine: RoutingTranslationEngine(), context: .live)
    var mode: Mode = .inPlace { didSet { if mode != oldValue, running { restart() } } }
    private(set) var running = false
    private(set) var paused = false
    private(set) var message = String(localized: "Choose a screen region for live translation")
    @ObservationIgnored private let selector = RegionSelector()
    @ObservationIgnored private let ocr = ScreenOCRService()
    @ObservationIgnored private lazy var hover = HoverTranslationController(ocr: ocr)
    @ObservationIgnored private lazy var inPlace = InPlaceTranslationController(ocr: ocr)
    /// Перевод виден поверх нужного приложения, поэтому окно Koto после запуска убирается.
    @ObservationIgnored var onStarted: (() -> Void)?
    @ObservationIgnored private var region: CGRect?
    @ObservationIgnored private var screenFrame: CGRect?
    @ObservationIgnored private var displayID: UInt32?

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
            self.resume()
            if self.running { self.onStarted?() }
        }
    }

    private func restart() { pause(); resume() }

    func resume() {
        guard let region, !running else { return }
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }), screen.frame == screenFrame, screen.frame.contains(region) else {
            message = CaptureFailure.invalidRegion.errorDescription ?? ""
            return
        }
        running = true; paused = false
        let pair: () -> (source: String, target: String) = { [weak self] in
            (self?.model.sourceIdentifier ?? "auto", self?.model.targetIdentifier ?? "ru")
        }
        let status: (String) -> Void = { [weak self] in self?.message = $0 }
        if model.languages.isEmpty { Task { await model.loadLanguages() } }
        switch mode {
        case .inPlace:
            message = String(localized: "Foreign text in the region is replaced by its translation right where it is.")
            inPlace.start(region: region, screen: screen, pair: pair, onStatus: status)
        case .hover:
            message = String(localized: "Point the cursor at a word in the region: the translation appears next to it.")
            hover.start(region: region, screen: screen, pair: pair, onStatus: status)
        }
    }

    func pause() {
        hover.stop(); inPlace.stop()
        running = false; paused = hasRegion
        message = String(localized: "Live translation paused")
    }

    func stop() {
        pause()
        selector.cancel()
        region = nil; screenFrame = nil; displayID = nil
        paused = false
        message = String(localized: "Live translation stopped")
    }

    /// Смена пары перезапускает режим: прежние переводы относились к другим языкам.
    func translationOptionsChanged() { if running { restart() } }

    func engineChanged() {
        let restartAfter = running
        pause()
        Task { await model.loadLanguages() }
        if restartAfter { resume() }
    }
}
