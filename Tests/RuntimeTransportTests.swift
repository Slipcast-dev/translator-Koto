import Foundation
import Darwin

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
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["status": "passed", "tests": passed]), as: UTF8.self))
    }
}
