import Foundation
import Darwin
import CryptoKit

/// Настоящие Unix-сокеты и kernel peer PID; подменяется только HTTP-сервер без модели.
@main struct RuntimeTransportTests {
    static func main() async throws {
        DispatchQueue.global().asyncAfter(deadline: .now() + 40) { exit(124) }
        let directory = URL(fileURLWithPath: "/tmp/koto-transport-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("runtime.sock").path
        // Настоящий launcher запускает fixture как единственный дочерний runtime.
        // Symlink нужен только тесту: production проверяет хеш реального llama-server.
        let runtime = directory.appendingPathComponent("llama-server")
        try FileManager.default.createSymbolicLink(atPath: runtime.path, withDestinationPath: CommandLine.arguments[3])
        var passed: [String] = []
        let source = directory.appendingPathComponent("fixture.gguf")
        let original = Data("GGUFverified-public-fixture".utf8)
        try original.write(to: source)
        let hash = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        let snapshot = try await LocalRuntimeSupervisor.modelSnapshot(source, expected: hash, expectedBytes: Int64(original.count))
        defer { try? snapshot.close() }
        // Проверяем и изменение того же inode, и атомарную замену исходного пути.
        try Data(repeating: 65, count: original.count).write(to: source)
        try Data(repeating: 66, count: original.count).write(to: source, options: .atomic)
        guard try snapshot.readToEnd() == original else { throw LocalRuntimeFailure.corrupt }
        var metadata = stat()
        guard fstat(snapshot.fileDescriptor, &metadata) == 0, metadata.st_nlink == 0 else { throw LocalRuntimeFailure.corrupt }
        try snapshot.seek(toOffset: 0)
        // Реальный launcher передаёт fd 0 через exec, как при запуске llama-server.
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: CommandLine.arguments[2])
        probe.arguments = [runtime.path, "-c", "import pathlib,sys; sys.stdout.buffer.write(pathlib.Path('/dev/fd/0').read_bytes())"]
        probe.standardInput = snapshot
        let probeOutput = Pipe()
        probe.standardOutput = probeOutput
        try probe.run()
        let inherited = probeOutput.fileHandleForReading.readDataToEndOfFile()
        probe.waitUntilExit()
        guard probe.terminationStatus == 0, inherited == original else { throw LocalRuntimeFailure.corrupt }
        passed.append("verified unlinked model survives original replacement and launcher exec")
        do {
            _ = try await LocalRuntimeSupervisor.modelSnapshot(source, expected: hash, expectedBytes: Int64(original.count))
            throw LocalRuntimeFailure.start
        } catch LocalRuntimeFailure.corrupt { passed.append("same-size corrupt model rejected") }
        // Один путь повторно занимает чужой сервер: проверка только на старте была бы недостаточна.
        for (mode, body, authorized) in [("trusted", Optional<Data>.none, false),
                                        ("trusted", Data("private translation fixture".utf8), true),
                                        ("impostor", nil, false),
                                        ("impostor", Data("private translation fixture".utf8), true)] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[2])
            process.arguments = [runtime.path, CommandLine.arguments[1], path, mode]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            defer { if process.isRunning { process.terminate() } }
            // Читаем ровно строку READY, не съедая следующий отчёт в том же pipe.
            var ready = Data()
            while ready.last != 10 {
                guard let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty else {
                    throw LocalRuntimeFailure.start
                }
                ready.append(byte)
            }
            guard String(decoding: ready, as: UTF8.self) == "READY\n" else { throw LocalRuntimeFailure.start }
            let endpoint = LocalEndpoint(socketPath: path, launcherPID: process.processIdentifier, token: "test-only-token")
            do {
                let (response, status) = try await LocalRuntimeTransport.request(endpoint,
                    path: body == nil ? "/health" : "/v1/chat/completions", body: body, authorized: authorized, timeout: 5)
                guard mode == "trusted", status == 200, response == Data("{}".utf8) else {
                    throw LocalRuntimeFailure.start
                }
            } catch LocalRuntimeFailure.corrupt {
                guard mode == "impostor" else { throw LocalRuntimeFailure.corrupt }
            }
            let reportData = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let report = try JSONSerialization.jsonObject(with: reportData) as? [String: Any],
                  let count = report["bytes"] as? Int, let hasAuth = report["authorized"] as? Bool,
                  mode == "impostor" ? count == 0 : (count > 0 && hasAuth == authorized) else {
                throw LocalRuntimeFailure.corrupt
            }
            passed.append("\(mode) \(body == nil ? "health" : "translation"): peer checked before bytes")
        }
        // Каталоги /tmp/koto-<UUID> после краха: мёртвый launcher удаляется, живой и чужое имя остаются.
        func makeDirectory(pid: Int32?) throws -> URL {
            let url = URL(fileURLWithPath: "/tmp/koto-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try Data("key\n".utf8).write(to: url.appendingPathComponent("api-key"))
            if let pid { try Data("\(pid)\n".utf8).write(to: url.appendingPathComponent("launcher.pid")) }
            return url
        }
        let dead = Process(); dead.executableURL = URL(fileURLWithPath: "/usr/bin/true"); try dead.run(); dead.waitUntilExit()
        let staleDirectory = try makeDirectory(pid: dead.processIdentifier)
        let liveDirectory = try makeDirectory(pid: getpid())
        let freshNoPid = try makeDirectory(pid: nil)
        let foreign = URL(fileURLWithPath: "/tmp/koto-not-a-uuid-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false)
        defer { for url in [staleDirectory, liveDirectory, freshNoPid, foreign] { try? FileManager.default.removeItem(at: url) } }
        LocalRuntimeSupervisor.removeStaleDirectories(except: nil)
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        guard !exists(staleDirectory), exists(liveDirectory), exists(freshNoPid), exists(foreign) else {
            throw NSError(domain: "RuntimeTransportTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "stale directory cleanup"])
        }
        passed.append("stale runtime directory removed; live, fresh and foreign directories kept")
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["status": "passed", "tests": passed]), as: UTF8.self))
    }
}
