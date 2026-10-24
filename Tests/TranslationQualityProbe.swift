import Foundation

struct QualityFixture: Decodable { let id: String; let source: String; let target: String; let text: String }

/// Публичные синтетические фразы, настоящие движки. Метрики не заменяют языковую экспертизу.
@main struct TranslationQualityProbe {
    static func main() async throws {
        DispatchQueue.global().asyncAfter(deadline:.now()+1800) { exit(124) }
        guard CommandLine.arguments.count >= 5 else { exit(64) }
        let resourceRoot = URL(fileURLWithPath:CommandLine.arguments[1])
        let spec = try JSONDecoder().decode(LocalModelManifest.self,from:Data(contentsOf:resourceRoot.appendingPathComponent("LocalModels/manifest.json")))
        let modelFile: URL
        if let option = CommandLine.arguments.firstIndex(of:"--model-file"), CommandLine.arguments.count > option + 1 {
            modelFile = URL(fileURLWithPath:CommandLine.arguments[option + 1])
        } else { modelFile = try LocalModelLocation.installedFile(for:spec) }
        let runtime = LocalRuntimeSupervisor(resourceRoot:resourceRoot,modelFile:modelFile)
        defer { runtime.stop() }
        let local = CommandLine.arguments[2] == "local"
        let engine: any TranslationEngine = local ? LocalTranslationEngine(runtime:runtime) : AppleTranslationEngine()
        var fixtures = try JSONDecoder().decode([QualityFixture].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3])))
        if CommandLine.arguments.contains("--long") {
            let paragraphs = (1...40).map { index in
                "Section \(index). The backup must not be deleted. The cat is sleeping on the chair. Please save the original document before you close the window. The server will restart at 09:30. This paragraph checks that the complete message is translated without missing the final sentence."
            }
            fixtures = [QualityFixture(id:"long-40-paragraphs",source:"en",target:"ru",text:paragraphs.joined(separator:"\n\n"))]
        }
        var records: [[String:Any]] = []
        for fixture in fixtures {
            let start = ContinuousClock.now
            var record: [String:Any] = ["id":fixture.id,"source":fixture.source,"target":fixture.target,
                "input":fixture.text,"input_characters":fixture.text.count]
            do {
                let request = try TranslationRequest(text:fixture.text,source:TranslationLanguage(id:fixture.source),target:TranslationLanguage(id:fixture.target))
                let readiness = try await engine.readiness(for:request)
                guard case .installed(let resolved) = readiness else {
                    record["status"] = "resources_not_installed"; records.append(record); continue
                }
                let result = try await engine.translate(resolved)
                record["status"] = "translated"; record["output"] = result.text
                record["output_characters"] = result.text.count
            } catch { record["status"] = "failed"; record["error"] = (error as? LocalizedError)?.errorDescription ?? "translation failure" }
            let elapsed = start.duration(to:.now).components
            record["milliseconds"] = Double(elapsed.seconds)*1000+Double(elapsed.attoseconds)/1e15
            records.append(record)
            // Частичный отчёт сохраняется после каждой фразы: холодная модель не теряет уже полученные доказательства.
            let report: [String:Any] = ["engine":local ? "Qwen3 4B" : "Apple Translation","results":records]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(
                to:URL(fileURLWithPath:CommandLine.arguments[4]),options:.atomic)
        }
    }
}
