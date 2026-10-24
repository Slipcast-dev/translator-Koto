import Foundation

/// Это отдельная CLI-проверка на фиксированных публичных фразах, не на пользовательском вводе.
@main
struct AppleTranslationProbe {
    @MainActor static func main() async {
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(90)) } catch { return }
            fputs("Apple Translation probe timed out.\n", stderr)
            exit(124)
        }
        defer { watchdog.cancel() }
        let samples: [(name: String, text: String, source: String?, target: String)] = [
            ("explicit_en_ru", "The cat is sleeping on the chair.", "en", "ru"),
            ("automatic_en_ru", "Good morning! This is a test of local translation.", nil, "ru"),
            ("explicit_ru_en", "Доброе утро! Кот спит на стуле.", "ru", "en")
        ]
        let engine = AppleTranslationEngine()
        var rows: [[String: Any]] = []
        var status = "passed"
        var exitCode: Int32 = 0
        do {
            for sample in samples {
                let request = try TranslationRequest(
                    text: sample.text,
                    source: sample.source.map { TranslationLanguage(id: $0) },
                    target: TranslationLanguage(id: sample.target)
                )
                switch try await engine.readiness(for: request) {
                case .needsDownload:
                    status = "requires_download"
                    exitCode = 3
                    rows.append(["scenario": sample.name, "models": "not_installed"])
                case .installed(let resolved):
                    let result = try await engine.translate(resolved)
                    guard result.requestID == request.id,
                          !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          result.text != sample.text else { throw TranslationFailure.failed }
                    rows.append([
                        "scenario": sample.name, "source": result.source.id,
                        "target": result.target.id, "input": sample.text, "output": result.text
                    ])
                }
                if exitCode != 0 { break }
            }
        } catch {
            status = "failed"
            exitCode = 1
            rows.append(["error": String(describing: error)])
        }
        let report: [String: Any] = ["status": status, "engine": "actual Apple Translation lowLatency", "scenarios": rows]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
        exit(exitCode)
    }
}
