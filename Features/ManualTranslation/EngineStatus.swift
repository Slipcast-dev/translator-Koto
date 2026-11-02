import Foundation
import Observation

/// Реальная готовность выбранного движка, а не заглушка «Ready».
/// Читает только наблюдаемые источники (выбор движка, установка модели, состояние runtime),
/// поэтому SwiftUI обновляет подпись при их изменении без опроса.
enum EngineReadiness: Equatable {
    case ready(String)
    case loading(String)
    case unavailable(String)

    var isReady: Bool { if case .ready = self { true } else { false } }
    var isLoading: Bool { if case .loading = self { true } else { false } }
    var text: String {
        switch self { case .ready(let value), .loading(let value), .unavailable(let value): value }
    }
}

@MainActor @Observable
final class EngineStatus {
    static let shared = EngineStatus()
    /// Keychain не наблюдаем: настройки ключа увеличивают счётчик, и подписи пересчитываются.
    private(set) var keychainRevision = 0
    func keychainChanged() { keychainRevision += 1 }

    /// Apple: статус зависит от каталога языков, который уже загружает модель перевода.
    func readiness(of kind: TranslationEngineKind, languagesLoaded: Bool, loadingLanguages: Bool,
                   catalogFailure: String?) -> EngineReadiness {
        switch kind {
        case .apple:
            if loadingLanguages { return .loading(String(localized: "Loading language list…")) }
            if let catalogFailure { return .unavailable(catalogFailure) }
            return languagesLoaded ? .ready(String(localized: "Ready"))
                : .unavailable(String(localized: "Language list is not loaded yet."))
        case .local:
            return localReadiness()
        case .google, .yandex:
            _ = keychainRevision
            let provider = kind == .google ? "google" : "yandex"
            return ProviderKeychain.exists(provider)
                ? .ready(String(localized: "Ready · API key saved"))
                : .unavailable(String(localized: "No API key. Add it in Settings → Cloud translation."))
        }
    }

    private func localReadiness() -> EngineReadiness {
        if ProcessInfo.processInfo.physicalMemory < 8 * 1_024 * 1_024 * 1_024 {
            return .unavailable(String(localized: "This local model requires a Mac with at least 8 GiB of memory."))
        }
        let models = ModelInstallationManager.shared
        guard models.specification != nil else {
            return .unavailable(String(localized: "The model catalog is damaged. Reinstall Koto from a trusted package."))
        }
        if models.isBusy { return .loading(String(localized: "Model is being installed…")) }
        guard models.isInstalled else {
            return .unavailable(String(localized: "Model not installed. Install it in Settings → Local translation."))
        }
        let runtime = LocalRuntimeSupervisor.shared
        return runtime.isRunning ? .ready(String(localized: "Ready · model loaded"))
            : .ready(String(localized: "Ready · model loads on first translation"))
    }
}
