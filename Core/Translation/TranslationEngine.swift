/// Engine boundary позволяет проверить гонки и ошибки без подмены реального движка в приложении.
/// MainActor явно задаёт владельца session.cancel и состояния запроса.
@MainActor
protocol TranslationEngine: AnyObject {
    var displayName: String { get }
    var requestTimeout: Duration { get }
    func supportedLanguages() async throws -> [TranslationLanguage]
    func readiness(for request: TranslationRequest) async throws -> TranslationReadiness
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
    func cancel()
}

// Совместимый default сохраняет существующие тестовые engine и системный движок.
extension TranslationEngine {
    var displayName: String { "Apple Translation" }
    var requestTimeout: Duration { .seconds(60) }
}
