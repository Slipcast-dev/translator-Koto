import Foundation
import NaturalLanguage
// Translation SDK экспортирует legacy async session без Sendable-аннотаций.
// Только этот импорт использует совместимость; Swift 6 strict concurrency проекта остаётся включён.
// Handle и cancel принадлежат MainActor, идентификатор защищает более новую session от старого defer.
@preconcurrency import Translation

/// Каталог, загрузка и перевод должны использовать одну стратегию.
/// SDK 26.4+ по умолчанию может выбрать Apple Intelligence; здесь нужен базовый локальный движок.
enum AppleTranslationPolicy {
    nonisolated static func availability() -> LanguageAvailability {
        if #available(macOS 26.4, *) {
            LanguageAvailability(preferredStrategy: .lowLatency)
        } else {
            LanguageAvailability()
        }
    }

    // Старый framework не объявляет LanguageAvailability как Sendable. Каждый запрос получает
    // отдельный экземпляр в nonisolated helper; наружу передаются только строки и Sendable status.
    nonisolated static func supportedIdentifiers() async -> [String] {
        let provider = availability()
        return await provider.supportedLanguages.map { $0.minimalIdentifier }
    }

    nonisolated static func status(source: String, target: String) async -> LanguageAvailability.Status {
        let provider = availability()
        return await provider.status(
            from: Locale.Language(identifier: source), to: Locale.Language(identifier: target)
        )
    }

    static func configuration(for request: TranslationRequest) -> TranslationSession.Configuration {
        if #available(macOS 26.4, *) {
            TranslationSession.Configuration(
                source: request.source?.localeLanguage,
                target: request.target.localeLanguage, preferredStrategy: .lowLatency
            )
        } else {
            TranslationSession.Configuration(
                source: request.source?.localeLanguage, target: request.target.localeLanguage
            )
        }
    }

    static func session(for request: TranslationRequest, source: TranslationLanguage) -> TranslationSession {
        if #available(macOS 26.4, *) {
            TranslationSession(
                installedSource: source.localeLanguage,
                target: request.target.localeLanguage, preferredStrategy: .lowLatency
            )
        } else {
            TranslationSession(installedSource: source.localeLanguage, target: request.target.localeLanguage)
        }
    }
}

/// Direct installedSource session не привязан к жизненному циклу SwiftUI view.
/// Для разрешения загрузки используется отдельная краткоживущая translationTask в sheet.
@MainActor
final class AppleTranslationEngine: TranslationEngine {
    private var session: TranslationSession?
    private var sessionRequestID: UUID?

    func supportedLanguages() async throws -> [TranslationLanguage] {
        let values = await AppleTranslationPolicy.supportedIdentifiers()
        try Task.checkCancellation()
        let result = Array(Set(values.map { TranslationLanguage(id: $0) }))
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        guard !result.isEmpty else { throw TranslationFailure.serviceUnavailable }
        return result
    }

    func readiness(for request: TranslationRequest) async throws -> TranslationReadiness {
        try Task.checkCancellation()
        let source: TranslationLanguage
        if let selected = request.source {
            source = selected
        } else {
            source = try await identifySource(in: request.text)
        }
        let resolved = try request.resolvingSource(source)
        let status = await AppleTranslationPolicy.status(source: source.id, target: request.target.id)
        try Task.checkCancellation()
        switch status {
        case .installed: return .installed(resolved)
        case .supported: return .needsDownload(resolved)
        case .unsupported: throw TranslationFailure.unsupportedPair
        @unknown default: throw TranslationFailure.serviceUnavailable
        }
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let source = request.source else { throw TranslationFailure.unableToIdentify }
        try Task.checkCancellation()
        let activeSession = AppleTranslationPolicy.session(for: request, source: source)
        session = activeSession
        sessionRequestID = request.id
        defer {
            // Завершение старого запроса не должно очищать session более нового запроса.
            if sessionRequestID == request.id {
                session = nil
                sessionRequestID = nil
            }
        }
        do {
            let response = try await activeSession.translate(request.text)
            try Task.checkCancellation()
            return TranslationResult(
                requestID: request.id, text: response.targetText,
                source: TranslationLanguage(id: response.sourceLanguage.minimalIdentifier),
                target: TranslationLanguage(id: response.targetLanguage.minimalIdentifier)
            )
        } catch {
            throw Self.failure(for: error)
        }
    }

    func cancel() {
        session?.cancel()
        session = nil
        sessionRequestID = nil
    }

    private func identifySource(in text: String) async throws -> TranslationLanguage {
        // NaturalLanguage выполняет определение на устройстве; короткая/смешанная фраза может быть неоднозначной.
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage,
              (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) >= 0.45 else {
            throw TranslationFailure.unableToIdentify
        }
        let available = try await supportedLanguages()
        let detected = TranslationLanguage(id: language.rawValue)
        if let exact = available.first(where: { $0.id == detected.id }) { return exact }
        guard let match = available.first(where: {
            $0.localeLanguage.languageCode == detected.localeLanguage.languageCode
        }) else { throw TranslationFailure.unsupportedPair }
        return match
    }

    /// Не выводим сырые ошибки framework: они не должны раскрывать текст или внутренние пути.
    static func failure(for error: Error) -> TranslationFailure {
        if let failure = error as? TranslationFailure { return failure }
        if error is CancellationError { return .cancelled }
        switch error {
        case TranslationError.alreadyCancelled: return .cancelled
        case TranslationError.notInstalled: return .modelsNotInstalled
        case TranslationError.unableToIdentifyLanguage: return .unableToIdentify
        case TranslationError.nothingToTranslate: return .emptyText
        case TranslationError.unsupportedSourceLanguage,
             TranslationError.unsupportedTargetLanguage,
             TranslationError.unsupportedLanguagePairing: return .unsupportedPair
        default: return .failed
        }
    }
}
