import Foundation

enum LocalProbeFailure: Error { case assertion(String) }

@main
struct LocalTranslationProbe {
    static func main() async {
        // Watchdog отдельный от MainActor, чтобы сбой системной загрузки не повесил проверку.
        DispatchQueue.global().asyncAfter(deadline: .now() + 300) { exit(124) }
        var report: [String: Any] = [:]
        do {
            guard CommandLine.arguments.count >= 2 else { throw LocalProbeFailure.assertion("resource root missing") }
            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("GGUFtest".utf8).write(to: scratch)
            defer { try? FileManager.default.removeItem(at: scratch) }
            do {
                try await LocalRuntimeSupervisor.verifyFile(scratch, expected: String(repeating: "0", count: 64), expectedBytes: 8, gguf: true)
                throw LocalProbeFailure.assertion("corruption accepted")
            } catch LocalRuntimeFailure.corrupt { report["corrupt_model_rejected"] = true }
            do {
                try await LocalRuntimeSupervisor.verifyFile(root.appendingPathComponent("missing-file"), expected: "")
                throw LocalProbeFailure.assertion("missing accepted")
            } catch LocalRuntimeFailure.missing { report["missing_file_rejected"] = true }
            let spec = try JSONDecoder().decode(LocalModelManifest.self,from:Data(contentsOf:root.appendingPathComponent("LocalModels/manifest.json")))
            let modelFile = try LocalModelLocation.installedFile(for:spec)
            let runtime = LocalRuntimeSupervisor(resourceRoot:root,modelFile:modelFile)
            defer { runtime.stop() }
            let endpoint = try await runtime.start()
            report["port"] = endpoint.port
            report["runtime_ready"] = true
            if CommandLine.arguments.contains("--crash") {
                // Результат не содержит API-key. Родительский тест проверит, что launcher убрал child.
                var record = try JSONSerialization.data(withJSONObject: report)
                record.append(10)
                FileHandle.standardOutput.write(record)
                try await Task.sleep(for: .seconds(2))
                kill(getpid(), SIGKILL)
            }
            var unauthorized = URLRequest(url: endpoint.baseURL.appendingPathComponent("v1/chat/completions"))
            unauthorized.httpMethod = "POST"
            unauthorized.setValue("application/json", forHTTPHeaderField: "Content-Type")
            unauthorized.httpBody = Data("{\"model\":\"local\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}".utf8)
            let (_, response) = try await runtime.session.data(for: unauthorized)
            guard (response as? HTTPURLResponse)?.statusCode == 401 else {
                throw LocalProbeFailure.assertion("unauthenticated request accepted")
            }
            report["unauthenticated_translation_rejected"] = true
            let engine = LocalTranslationEngine(runtime: runtime)
            var translations: [[String: String]] = []
            for (sourceID, targetID, text) in [
                ("en", "ru", "The cat is sleeping on the chair."),
                ("auto", "ru", "Good morning! This is a test of local translation."),
                ("ru", "en", "Доброе утро! Кот спит на стуле.")
            ] {
                let request = try TranslationRequest(text: text,
                    source: sourceID == "auto" ? nil : TranslationLanguage(id: sourceID),
                    target: TranslationLanguage(id: targetID))
                let readiness = try await engine.readiness(for: request)
                guard case .installed(let resolved) = readiness else { throw LocalProbeFailure.assertion("not ready") }
                let result = try await engine.translate(resolved)
                guard result.requestID == request.id, result.text != text, !result.text.isEmpty else {
                    throw LocalProbeFailure.assertion("invalid translation")
                }
                if targetID == "ru" {
                    guard result.text.range(of: "[\\p{Han}\\p{Hiragana}\\p{Katakana}]", options: .regularExpression) == nil else {
                        throw LocalProbeFailure.assertion("unexpected script in Russian fixture")
                    }
                }
                translations.append(["source": sourceID, "target": targetID, "input": text, "output": result.text])
            }
            report["translations"] = translations
            let long = try TranslationRequest(text: String(repeating: "The cat is sleeping on the chair. ", count: 140),
                source: TranslationLanguage(id: "en"), target: TranslationLanguage(id: "ru"))
            let pending = Task { try await engine.translate(long) }
            try await Task.sleep(for: .milliseconds(100))
            engine.cancel()
            do {
                _ = try await pending.value
                report["cancel"] = "completed_before_cancellation"
            } catch TranslationFailure.cancelled { report["cancel"] = "passed" }
            runtime.stop()
            try await Task.sleep(for: .seconds(2))
            var check = URLRequest(url: endpoint.baseURL.appendingPathComponent("health"))
            check.timeoutInterval = 1
            if (try? await runtime.session.data(for: check)) != nil {
                throw LocalProbeFailure.assertion("runtime still listening after stop")
            }
            report["stop_closes_port"] = true
            report["status"] = "passed"
        } catch {
            report["status"] = "failed"
            report["error"] = String(describing: error)
        }
        do {
            print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        } catch { exit(2) }
        if report["status"] as? String != "passed" { exit(1) }
    }
}
