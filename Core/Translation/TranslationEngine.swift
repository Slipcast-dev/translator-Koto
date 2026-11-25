/// Engine boundary позволяет проверить гонки и ошибки без подмены реального движка в приложении.
/// MainActor явно задаёт владельца session.cancel и состояния запроса.
@MainActor
protocol TranslationEngine: AnyObject {
    var displayName: String { get }
    var requestTimeout: Duration { get }
    func supportedLanguages() async throws -> [TranslationLanguage]
    func readiness(for request: TranslationRequest) async throws -> TranslationReadiness
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
    /// Движки, переводящие по частям, сообщают о готовых частях до завершения всего запроса.
    func translate(_ request: TranslationRequest, progress: @escaping TranslationProgressHandler) async throws -> TranslationResult
    func cancel()
}

/// Незавершённый перевод. Это не результат: его нельзя копировать, озвучивать и сохранять в память.
struct TranslationProgress: Sendable, Equatable {
    let completed: Int
    let total: Int
    let partialText: String
    var fraction: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
}
typealias TranslationProgressHandler = @MainActor (TranslationProgress) -> Void

// Совместимый default сохраняет существующие тестовые engine и системный движок.
extension TranslationEngine {
    var displayName: String { "Apple Translation" }
    var requestTimeout: Duration { .seconds(60) }
    func translate(_ request: TranslationRequest, progress: @escaping TranslationProgressHandler) async throws -> TranslationResult {
        try await translate(request)
    }
}
