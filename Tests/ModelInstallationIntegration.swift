import Foundation

/// Полная установка ранее скачанного выбранного GGUF и отдельная настоящая HTTPS-загрузка с отменой.
/// Веса после теста удаляются, пользовательский каталог production не затрагивается.
@main struct ModelInstallationIntegration {
    static func main() async {
        do { try await run() }
        catch {
            let result: [String:Any] = ["status":"failed","error":String(reflecting:error)]
            if let data = try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {
                FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
            }
            exit(1)
        }
    }
    static func run() async throws {
        DispatchQueue.global().asyncAfter(deadline:.now()+180) { exit(124) }
        let catalog = URL(fileURLWithPath:CommandLine.arguments[1])
        let source = URL(fileURLWithPath:CommandLine.arguments[2])
        let spec = try JSONDecoder().decode(LocalModelManifest.self,from:Data(contentsOf:catalog))
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("koto-install-integration-"+UUID().uuidString)
        try PrivateStorage.ensureDirectory(scratch)
        defer { try? FileManager.default.removeItem(at:scratch) }
        var report: [String:Any] = [:]
        guard let url = spec.url, let response = HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil) else { exit(1) }
        let installed = scratch.appendingPathComponent("installed",isDirectory:true)
        let manager = ModelInstallationManager(specification:spec,directory:installed,download:{ _,_ in
            let copy = scratch.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at:source,to:copy)
            return (copy,response)
        })
        manager.install()
        let deadline = ContinuousClock.now.advanced(by:.seconds(120))
        while manager.isBusy, ContinuousClock.now < deadline { try await Task.sleep(for:.milliseconds(100)) }
        guard manager.isInstalled, !manager.isBusy else { print("Full install status: " + manager.status); exit(1) }
        report["full_real_GGUF_hash_and_atomic_install"] = "passed"
        manager.remove()
        guard !manager.isInstalled else { exit(1) }
        report["remove_real_model"] = "passed"
        // Этот manager использует настоящий URLSession и CDN redirects, а не injected transport.
        let networkDirectory = scratch.appendingPathComponent("network",isDirectory:true)
        let network = ModelInstallationManager(specification:spec,directory:networkDirectory)
        network.install()
        let networkDeadline = ContinuousClock.now.advanced(by:.seconds(60))
        while network.isBusy, network.downloadedBytes < 262_144, ContinuousClock.now < networkDeadline {
            try await Task.sleep(for:.milliseconds(50))
        }
        let bytes = network.downloadedBytes
        network.cancel()
        let cancelledDeadline = ContinuousClock.now.advanced(by:.seconds(10))
        while network.isBusy, ContinuousClock.now < cancelledDeadline { try await Task.sleep(for:.milliseconds(50)) }
        guard bytes > 0, !network.isBusy, !network.isInstalled else {
            throw NSError(domain:"ModelNetworkIntegration",code:1,userInfo:[NSLocalizedDescriptionKey:"bytes=\(bytes), busy=\(network.isBusy), installed=\(network.isInstalled), status=\(network.status)"])
        }
        guard (try FileManager.default.contentsOfDirectory(atPath:networkDirectory.path)).isEmpty else { exit(1) }
        report["real_HTTPS_download_progress_bytes"] = bytes
        report["cancel_real_network_without_activated_model"] = "passed"
        report["status"] = "passed"
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
