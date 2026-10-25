import Foundation

@main
struct BrowserBridgeHarness {
    static func main() async {
        guard (2...3).contains(CommandLine.arguments.count) else { exit(64) }
        let mode = CommandLine.arguments.count == 3 ? CommandLine.arguments[2] : "real"
        guard ["real", "runtime-missing", "readiness-missing", "runtime-failed", "cloud-denied"].contains(mode) else { exit(64) }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let server = BrowserBridgeServer(directory: root, makeEngine: {
            if mode == "real" { return AppleTranslationEngine() }
            return ResourceFailureEngine(mode: mode)
        })
        server.start()
        for _ in 0..<100 {
            if server.status == String(localized: "Browser bridge is ready") {
                FileHandle.standardOutput.write(Data("{\"status\":\"ready\"}\n".utf8))
                while true { try? await Task.sleep(for: .seconds(3600)) }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        FileHandle.standardError.write(Data("bridge_not_ready\n".utf8))
        server.stop()
        exit(1)
    }
}

/// Подменяется только граница переводчика: framing, HELLO и ответ сервера остаются настоящими.
/// Так можно проверить исчезновение ресурсов без удаления системных моделей на Mac пользователя.
@MainActor
private final class ResourceFailureEngine: TranslationEngine {
    private let mode: String
    init(mode: String) { self.mode = mode }
    func supportedLanguages() async throws -> [TranslationLanguage] {
        [TranslationLanguage(id: "en"), TranslationLanguage(id: "ru")]
    }
    func readiness(for request: TranslationRequest) async throws -> TranslationReadiness {
        if mode == "cloud-denied" { throw TranslationFailure.cloudNotAllowed }
        let resolved = try request.resolvingSource(request.source ?? TranslationLanguage(id: "en"))
        return mode == "readiness-missing" ? .needsDownload(resolved) : .installed(resolved)
    }
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        throw mode == "runtime-failed" ? TranslationFailure.failed : TranslationFailure.modelsNotInstalled
    }
    func cancel() {}
}
