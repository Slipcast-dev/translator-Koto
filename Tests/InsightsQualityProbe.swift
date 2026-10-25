import Foundation
@main struct InsightsQualityProbe {
    static func main() async throws {
        DispatchQueue.global().asyncAfter(deadline:.now()+900) { exit(124) }
        let resourceRoot = URL(fileURLWithPath:CommandLine.arguments[1])
        let spec = try JSONDecoder().decode(LocalModelManifest.self,from:Data(contentsOf:resourceRoot.appendingPathComponent("LocalModels/manifest.json")))
        let modelFile: URL
        if let option = CommandLine.arguments.firstIndex(of:"--model-file"), CommandLine.arguments.count > option + 1 {
            modelFile = URL(fileURLWithPath:CommandLine.arguments[option + 1])
        } else { modelFile = try LocalModelLocation.installedFile(for:spec) }
        let runtime = LocalRuntimeSupervisor(resourceRoot:resourceRoot,modelFile:modelFile)
        defer { runtime.stop() }
        var records: [[String:Any]] = []
        for (text,alternatives) in [
            ("The cat is sleeping on the chair.",false),
            ("Кот спит на стуле.",false),
            ("Let's break the ice before we discuss the project.",false),
            ("I have been waiting for two hours.",false),
            ("The cat is sleeping on the chair.",true)
        ] {
            var record: [String:Any] = ["input":text,"alternatives_requested":alternatives]
            do {
                let result = try await LocalInsightsService(runtime:runtime).explain(text:text,target:"ru",alternatives:alternatives,explanationLanguage:"ru")
                record["status"] = "accepted";record["result"] = result.rendered
            } catch { record["status"] = "rejected";record["error"] = String(reflecting:error) }
            records.append(record)
            try JSONSerialization.data(withJSONObject:["results":records],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]),options:.atomic)
        }
    }
}
