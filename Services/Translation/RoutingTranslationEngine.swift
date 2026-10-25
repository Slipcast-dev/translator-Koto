import Foundation
import Observation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

enum TranslationEngineKind: String, CaseIterable, Identifiable {
    case apple, local, google, yandex
    var id: String { rawValue }
    var title: String {
        switch self { case .apple: "Apple Translation"; case .local: String(localized: "Qwen · local")
        case .google: "Google Cloud"; case .yandex: "Yandex Cloud" }
    }
    var isCloud: Bool { self == .google || self == .yandex }
}

@MainActor @Observable
final class EnginePreferences {
    static let shared = EnginePreferences()
    var selected: TranslationEngineKind {
        didSet { UserDefaults.standard.set(selected.rawValue, forKey: "translation.engine") }
    }
    init() {
        selected = TranslationEngineKind(rawValue: UserDefaults.standard.string(forKey: "translation.engine") ?? "") ?? .apple
    }
}

/// Снимок выбранного движка закрепляется за request ID; смена UI не переключает старый запрос.
@MainActor
final class RoutingTranslationEngine: TranslationEngine {
    private let apple = AppleTranslationEngine()
    private let local = LocalTranslationEngine()
    private let google = CloudTranslationEngine(.google)
    private let yandex = CloudTranslationEngine(.yandex)
    private var snapshots: [UUID: any TranslationEngine] = [:]
    private var selected: any TranslationEngine {
        switch EnginePreferences.shared.selected { case .apple: apple; case .local: local; case .google: google; case .yandex: yandex }
    }
    var displayName: String { EnginePreferences.shared.selected.title }
    var requestTimeout: Duration { EnginePreferences.shared.selected == .local ? .seconds(600) : .seconds(60) }

    func supportedLanguages() async throws -> [TranslationLanguage] { try await selected.supportedLanguages() }
    func readiness(for request: TranslationRequest) async throws -> TranslationReadiness {
        if let (record, title) = TranslationStore.shared.lookup(request) {
            snapshots[request.id] = StoredPhraseEngine(record, title: title)
            return .installed(request)
        }
        guard !EnginePreferences.shared.selected.isCloud || TranslationPrivacy.cloudAllowed(request.context) else {
            throw TranslationFailure.cloudNotAllowed
        }
        let engine = selected
        let readiness = try await engine.readiness(for: request)
        try Task.checkCancellation()
        snapshots[request.id] = engine
        return readiness
    }
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let engine = snapshots.removeValue(forKey: request.id) else { throw TranslationFailure.cancelled }
        if engine is CloudTranslationEngine, !TranslationPrivacy.cloudAllowed(request.context) {
            throw TranslationFailure.cloudNotAllowed
        }
        let translated = try await engine.translate(request)
        try Task.checkCancellation()
        let result = TranslationResult(requestID: translated.requestID, text: translated.text,
            source: translated.source, target: translated.target, engineLabel: translated.engineLabel ?? engine.displayName)
        TranslationStore.shared.remember(request, result: result)
        return result
    }
    func cancel() {
        snapshots.removeAll()
        apple.cancel()
        local.cancel()
        google.cancel(); yandex.cancel()
    }
}
