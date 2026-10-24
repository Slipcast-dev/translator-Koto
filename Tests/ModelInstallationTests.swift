import Foundation
import CryptoKit
import Darwin

enum ModelTestError: Error { case assertion(String) }

/// Реальная файловая установка и SHA-256. Только транспорт заменяется локальным публичным fixture.
@main struct ModelInstallationTests {
    static func wait(_ manager: ModelInstallationManager) async throws {
        let deadline = ContinuousClock.now.advanced(by:.seconds(15))
        while manager.isBusy, ContinuousClock.now < deadline { try await Task.sleep(for:.milliseconds(10)) }
        guard !manager.isBusy else { throw ModelTestError.assertion("installer stalled") }
    }
    static func main() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("koto-model-tests-" + UUID().uuidString)
        try PrivateStorage.ensureDirectory(scratch)
        defer { try? FileManager.default.removeItem(at:scratch) }
        var passed: [String] = []
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw ModelTestError.assertion(name) }; passed.append(name)
        }
        let bytes = Data("GGUFpublic-test-fixture".utf8)
        let hash = SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
        let revision = String(repeating:"a",count:40)
        let url = URL(string:"https://huggingface.co/fixture/model/resolve/\(revision)/fixture.gguf")!
        let spec = LocalModelManifest(id:"fixture-q4_k_m",filename:"fixture.gguf",sha256:hash,bytes:Int64(bytes.count),
            revision:revision,repository:"fixture/model",url:url,license:"Apache-2.0",displayName:"Fixture")
        let modelDir = scratch.appendingPathComponent("installed")
        let makeFile: () throws -> URL = {
            let file = scratch.appendingPathComponent(UUID().uuidString)
            try bytes.write(to:file); return file
        }
        let response = HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil)!
        let manager = ModelInstallationManager(specification:spec,directory:modelDir,download:{ _,_ in (try makeFile(),response) })
        try check(!manager.isInstalled && !manager.isBusy,"no automatic model download")
        manager.install(); try await wait(manager)
        try check(manager.isInstalled,"one action installs checked model")
        let installed = modelDir.appendingPathComponent(spec.filename)
        try check(try Data(contentsOf:installed) == bytes,"published bytes match fixture")
        var info = stat(); _ = lstat(installed.path,&info)
        try check(info.st_mode & 0o777 == 0o600,"model file is private 0600")
        try check((try FileManager.default.contentsOfDirectory(atPath:modelDir.path)).allSatisfy { !$0.hasPrefix(".install-") },"staging cleaned after success")
        manager.remove()
        try check(!manager.isInstalled && !FileManager.default.fileExists(atPath:installed.path),"remove deletes only installed model")
        let corrupt = ModelInstallationManager(specification:spec,directory:modelDir,download:{ _,_ in
            let file = try makeFile(); try Data(repeating:0,count:bytes.count).write(to:file); return (file,response)
        })
        corrupt.install(); try await wait(corrupt)
        try check(!corrupt.isInstalled && !FileManager.default.fileExists(atPath:installed.path),"same-size corrupt hash is not activated")
        try check((try FileManager.default.contentsOfDirectory(atPath:modelDir.path)).isEmpty,"failed download leaves no model or staging")
        let cancelled = ModelInstallationManager(specification:spec,directory:modelDir,download:{ _,_ in
            try await Task.sleep(for:.seconds(10)); return (try makeFile(),response)
        })
        cancelled.install(); try await Task.sleep(for:.milliseconds(30)); cancelled.cancel(); try await wait(cancelled)
        try check(!cancelled.isInstalled && !FileManager.default.fileExists(atPath:installed.path),"cancel leaves no activated model")
        let outside = scratch.appendingPathComponent("unrelated.txt"); try Data("keep".utf8).write(to:outside)
        try FileManager.default.createSymbolicLink(at:installed,withDestinationURL:outside)
        manager.remove()
        try check(try String(contentsOf:outside,encoding:.utf8) == "keep","remove never follows symlink")
        try FileManager.default.removeItem(at:installed)
        let unsafeDirectory = scratch.appendingPathComponent("symlink-directory")
        try FileManager.default.createSymbolicLink(at:unsafeDirectory,withDestinationURL:modelDir)
        let unsafe = ModelInstallationManager(specification:spec,directory:unsafeDirectory,download:{ _,_ in (try makeFile(),response) })
        unsafe.install(); try await wait(unsafe)
        try check(!unsafe.isInstalled,"symlink model directory refused")
        try check(ModelDownloadPolicy.allows(URL(string:"https://cas-bridge.xethub.hf.co/file")!),"vendor HTTPS CDN allowed")
        try check(!ModelDownloadPolicy.allows(URL(string:"http://huggingface.co/file")!),"HTTP redirect refused")
        try check(!ModelDownloadPolicy.allows(URL(string:"https://huggingface.co.attacker.example/file")!),"lookalike host refused")
        try check(!ModelDownloadPolicy.allows(URL(string:"https://user:password@huggingface.co/file")!),"credential URL refused")
        print(String(decoding:try JSONSerialization.data(withJSONObject:["status":"passed","count":passed.count,"tests":passed],options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
