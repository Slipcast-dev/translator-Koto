import Foundation

/// Клиент Safari проверяется против настоящего сервера моста (harness) через AF_UNIX с HELLO и токеном.
@main struct SafariBridgeClientTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    nonisolated(unsafe) static var passed: [String] = []

    static func check(_ condition: Bool, _ name: String) throws {
        guard condition else { throw Failure(description: "FAILED: " + name) }
        passed.append(name)
    }

    static func startServer(harness: String, directory: URL, mode: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: harness)
        process.arguments = [directory.path, mode]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let line = output.fileHandleForReading.availableData
        guard String(decoding: line, as: UTF8.self).contains("ready") else {
            process.terminate(); throw Failure(description: "server did not start in mode \(mode)")
        }
        return process
    }

    static func translate(_ directory: URL, text: String = "The cat is sleeping.") -> Result<String, SafariBridgeClient.Failure> {
        do {
            return .success(try SafariBridgeClient.translate(
                text: text, source: "en", target: "ru", pageOrigin: "https://example.com", directory: directory.path, timeout: 8))
        } catch let failure as SafariBridgeClient.Failure { return .failure(failure) }
        catch { return .failure(.init(code: "other")) }
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw Failure(description: "usage: tests <bridge-harness>") }
        let harness = CommandLine.arguments[1]
        let root = URL(fileURLWithPath: "/tmp/koto-safari-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }

        // Пути сокета совпадают с приложением: длинный путь переносится в /tmp по тому же правилу.
        let longDirectory = root.appendingPathComponent(String(repeating: "д", count: 60), isDirectory: true).path
        try check(SafariBridgeClient.socketPath(directory: longDirectory).hasPrefix("/tmp/koto-bridge-\(getuid())-"), "long path uses the short socket directory")
        try check(SafariBridgeClient.socketPath(directory: "/a/b") == "/a/b/bridge.sock", "short path stays in the bridge directory")

        // Сервер не запущен: клиент не зависает и просит запустить приложение ровно один раз.
        let empty = root.appendingPathComponent("none", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        nonisolated(unsafe) var launches = 0
        let began = Date()
        do {
            _ = try SafariBridgeClient.translate(text: "x", source: "en", target: "ru", pageOrigin: "https://example.com",
                                                 directory: empty.path, timeout: 2, launchApp: { launches += 1 })
            throw Failure(description: "translate succeeded without a server")
        } catch let failure as SafariBridgeClient.Failure {
            try check(failure.code == "native_host_unavailable", "no server reports native_host_unavailable")
        }
        try check(launches == 1 && Date().timeIntervalSince(began) < 6, "app launch requested once and no hang")

        for (mode, code) in [("readiness-missing", "models_missing"), ("cloud-denied", "cloud_not_allowed"), ("runtime-failed", "translation_failed")] {
            let directory = root.appendingPathComponent(mode, isDirectory: true)
            let server = try startServer(harness: harness, directory: directory, mode: mode)
            defer { server.terminate(); server.waitUntilExit() }
            switch translate(directory) {
            case .failure(let failure): try check(failure.code == code, "\(mode) maps to \(code)")
            case .success: throw Failure(description: "\(mode) unexpectedly translated")
            }
        }

        // Реальный Apple Translation: допустим и перевод, и отсутствие языковых ресурсов (состояние среды).
        let real = root.appendingPathComponent("real", isDirectory: true)
        let server = try startServer(harness: harness, directory: real, mode: "real")
        defer { server.terminate(); server.waitUntilExit() }
        switch translate(real, text: "The cat is sleeping on the chair.") {
        case .success(let text): try check(!text.isEmpty, "real translation returned text over the Safari client")
        case .failure(let failure): try check(failure.code == "models_missing" || failure.code == "translation_failed", "real engine environment limit: \(failure.code)")
        }
        // Неверный токен: сервер закрывает соединение, клиент получает ошибку, а не зависает.
        try Data("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=".utf8).write(to: real.appendingPathComponent("bridge.token"), options: [])
        _ = chmod(real.appendingPathComponent("bridge.token").path, 0o600)
        switch translate(real) {
        case .failure: passed.append("wrong token rejected without hanging")
        case .success: throw Failure(description: "wrong token accepted")
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["status": "passed", "tests": passed], options: [.sortedKeys]), as: UTF8.self))
    }
}
