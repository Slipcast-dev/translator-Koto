import AppKit
import AVFoundation
import Observation
import ServiceManagement

/// Озвучивание запускается только явной кнопкой, использует установленный голос macOS.
@MainActor @Observable
final class SpeechController {
    static let shared = SpeechController()
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var status = ""
    func speak(_ result: TranslationResult) {
        stop()
        guard let voice = AVSpeechSynthesisVoice(language: result.target.id) else { status = "Установите голос этого языка в macOS"; return }
        let utterance = AVSpeechUtterance(string: result.text)
        utterance.voice = voice
        synthesizer.speak(utterance)
        status = "Озвучивание запущено"
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate); status = "" }
}

enum ProductUtilities {
    static var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func setLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
    /// Экспортируется whitelist метаданных: без текста, ключей, путей и истории пользователя.
    static func exportDiagnostics() throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Koto-diagnostics.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let record: [String: Any] = ["product": ProductInfo.name, "developer": ProductInfo.developer,
            "version": ProductInfo.version, "build": ProductInfo.build,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "engine": EnginePreferences.shared.selected.rawValue,
            "accessibility": AXIsProcessTrusted(), "screen_capture": CGPreflightScreenCaptureAccess(),
            "memory_opt_in": TranslationStore.shared.memoryEnabled,
            "bridge_enabled": UserDefaults.standard.bool(forKey: "browserBridge.enabled")]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}
