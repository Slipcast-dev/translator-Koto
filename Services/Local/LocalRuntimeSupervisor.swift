import Foundation
import Observation
import CryptoKit
import Security
import Darwin

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

enum LocalRuntimeFailure: Error, LocalizedError {
    case missing, corrupt, memory, start, timeout, stopped
    var errorDescription: String? {
        switch self {
        case .missing: String(localized: "Local resources are missing. Open Koto Settings → Local translation → Install model.")
        case .corrupt: String(localized: "Local resource verification failed. The file will not be launched.")
        case .memory: String(localized: "This local model requires a Mac with at least 8 GiB of memory.")
        case .start: String(localized: "Unable to start the local engine.")
        case .timeout: String(localized: "The local engine did not become ready within 120 seconds.")
        case .stopped: String(localized: "The local engine stopped.")
        }
    }
}

struct LocalModelManifest: Codable, Sendable {
    let id: String
    let filename: String
    let sha256: String
    let bytes: Int64
    let revision: String
    let repository: String?
    let url: URL?
    let license: String?
    let displayName: String?
}

/// Production читает веса только из пользовательского Application Support, никогда из app bundle.
enum LocalModelLocation {
    nonisolated static func isSafe(_ spec: LocalModelManifest) -> Bool {
        spec.id.range(of:"^[a-z0-9][a-z0-9_-]{0,95}$",options:.regularExpression) != nil
            && spec.filename == URL(fileURLWithPath:spec.filename).lastPathComponent
            && !spec.filename.contains("/") && !spec.filename.contains("\\") && spec.filename.hasSuffix(".gguf")
            && spec.sha256.range(of:"^[a-fA-F0-9]{64}$",options:.regularExpression) != nil
            && spec.revision.range(of:"^[a-fA-F0-9]{40}$",options:.regularExpression) != nil
            && spec.bytes > 4 && spec.bytes <= 20_000_000_000
    }
    static func installedFile(for spec: LocalModelManifest) throws -> URL {
        guard isSafe(spec), let support = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first else {
            throw LocalRuntimeFailure.corrupt
        }
        return support.appendingPathComponent("dev.slipcast.koto/Models",isDirectory:true)
            .appendingPathComponent(spec.id,isDirectory:true).appendingPathComponent(spec.filename)
    }
}

struct LocalEndpoint: Sendable {
    let port: Int
    let token: String
    let baseURL: URL
    init(port: Int, token: String) throws {
        guard (1024...65535).contains(port), !token.isEmpty,
              let url = URL(string: "http://127.0.0.1:\(port)") else { throw LocalRuntimeFailure.start }
        self.port = port
        self.token = token
        self.baseURL = url
    }
}

/// Запрещаем redirects даже с loopback: перевод нельзя незаметно перенаправить наружу.
final class LocalNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Supervisor владеет launcher, ключом и endpoint. Child не получает токен через argv или env.
@MainActor @Observable
final class LocalRuntimeSupervisor {
    static let shared = LocalRuntimeSupervisor()
    private(set) var status = String(localized: "Local engine stopped")
    private(set) var isRunning = false
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var endpoint: LocalEndpoint?
    @ObservationIgnored private var starting: Task<LocalEndpoint, Error>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var privateDirectory: URL?
    @ObservationIgnored private let resourceRoot: URL
    @ObservationIgnored private let modelFileOverride: URL?
    @ObservationIgnored let session: URLSession

    init(resourceRoot: URL? = nil, modelFile: URL? = nil) {
        self.modelFileOverride = modelFile
        self.resourceRoot = resourceRoot ?? Bundle.main.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 90
        session = URLSession(configuration: config, delegate: LocalNoRedirectDelegate(), delegateQueue: nil)
    }

    func start() async throws -> LocalEndpoint {
        if let starting { return try await starting.value }
        if let endpoint, process?.isRunning == true { return endpoint }
        let id = UUID()
        generation = id
        let task = Task { try await launch(id: id) }
        starting = task
        defer { if generation == id { starting = nil } }
        return try await task.value
    }

    private func launch(id: UUID) async throws -> LocalEndpoint {
        do {
            status = String(localized: "Verifying local resources…")
            guard ProcessInfo.processInfo.physicalMemory >= 8 * 1_024 * 1_024 * 1_024 else {
                throw LocalRuntimeFailure.memory
            }
            let modelDirectory = resourceRoot.appendingPathComponent("LocalModels", isDirectory: true)
            let manifestURL = modelDirectory.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw LocalRuntimeFailure.missing }
            let spec = try JSONDecoder().decode(LocalModelManifest.self, from: Data(contentsOf: manifestURL))
            guard LocalModelLocation.isSafe(spec) else { throw LocalRuntimeFailure.corrupt }
            let model = try modelFileOverride ?? LocalModelLocation.installedFile(for:spec)
            let runtimeDirectory = resourceRoot.appendingPathComponent("LocalRuntime", isDirectory: true)
            let runtime = runtimeDirectory.appendingPathComponent("llama-server")
            let launcher = runtimeDirectory.appendingPathComponent("koto-runtime-launcher")
            let runtimeSpec = try JSONDecoder().decode([String: String].self,
                from: Data(contentsOf: runtimeDirectory.appendingPathComponent("manifest.json")))
            guard let runtimeHash = runtimeSpec["runtimeSHA256"], let launcherHash = runtimeSpec["launcherSHA256"] else {
                throw LocalRuntimeFailure.corrupt
            }
            try await Self.verifyFile(model, expected: spec.sha256, expectedBytes: spec.bytes, gguf: true)
            try await Self.verifyFile(runtime, expected: runtimeHash)
            try await Self.verifyFile(launcher, expected: launcherHash)
            try Task.checkCancellation()
            guard generation == id else { throw CancellationError() }
            let port = try Self.availablePort()
            var random = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
                throw LocalRuntimeFailure.start
            }
            let token = Data(random).base64EncodedString()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("dev.slipcast.koto-runtime-" + UUID().uuidString, isDirectory: true)
            guard mkdir(directory.path, 0o700) == 0 else { throw LocalRuntimeFailure.start }
            privateDirectory = directory
            let keyFile = directory.appendingPathComponent("api-key")
            let fd = open(keyFile.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw LocalRuntimeFailure.start }
            let key = Data((token + "\n").utf8)
            let written = key.withUnsafeBytes { bytes in
                Darwin.write(fd, bytes.baseAddress, bytes.count)
            }
            close(fd)
            guard written == key.count else { throw LocalRuntimeFailure.start }
            let child = Process()
            child.executableURL = launcher
            child.arguments = [runtime.path, "--model", model.path, "--host", "127.0.0.1",
                "--port", String(port), "--api-key-file", keyFile.path, "--ctx-size", "4096",
                "--parallel", "1", "--threads", "4", "--n-gpu-layers", "99",
                "--no-webui", "--offline", "--log-disable"]
            // Исключаем унаследованные LLAMA_* и proxy настройки внешнего окружения.
            child.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(),
                                 "TMPDIR": FileManager.default.temporaryDirectory.path]
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            child.standardInput = FileHandle.nullDevice
            child.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == id else { return }
                    self.isRunning = false
                    self.endpoint = nil
                    self.status = String(localized: "Local engine exited")
                    self.cleanupKey()
                }
            }
            process = child
            try child.run()
            let ready = try LocalEndpoint(port: port, token: token)
            status = String(localized: "Loading local model…")
            let until = ContinuousClock.now.advanced(by: .seconds(120))
            while ContinuousClock.now < until {
                try Task.checkCancellation()
                guard generation == id, child.isRunning else { throw LocalRuntimeFailure.start }
                var request = URLRequest(url: ready.baseURL.appendingPathComponent("health"))
                request.timeoutInterval = 2
                request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                if let (_, response) = try? await session.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode == 200 {
                    endpoint = ready
                    isRunning = true
                    status = String(localized: "\(spec.displayName ?? "Qwen3 4B Instruct 2507") · on this Mac")
                    return ready
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            throw LocalRuntimeFailure.timeout
        } catch {
            if generation == id { stop(); status = (error as? LocalRuntimeFailure)?.errorDescription ?? String(localized: "Local engine unavailable") }
            throw error
        }
    }

    func stop() {
        generation = UUID()
        starting?.cancel(); starting = nil
        if let process, process.isRunning { process.terminate() }
        // Launcher завершает llama-server и reap даже при crash GUI; не блокируем MainActor ожиданием.
        process = nil
        endpoint = nil
        isRunning = false
        status = String(localized: "Local engine stopped")
        cleanupKey()
    }

    private func cleanupKey() {
        guard let directory = privateDirectory else { return }
        // Удаляем только созданный этой операцией файл и пустой UUID-каталог.
        unlink(directory.appendingPathComponent("api-key").path)
        rmdir(directory.path)
        privateDirectory = nil
    }

    nonisolated static func verifyFile(_ url: URL, expected: String, expectedBytes: Int64? = nil, gguf: Bool = false) async throws {
        let worker = Task.detached(priority: .utility) {
            var info = stat()
            guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
                throw LocalRuntimeFailure.missing
            }
            if let expectedBytes, info.st_size != expectedBytes { throw LocalRuntimeFailure.corrupt }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            if gguf {
                guard try file.read(upToCount: 4) == Data("GGUF".utf8) else { throw LocalRuntimeFailure.corrupt }
                try file.seek(toOffset: 0)
            }
            var hash = SHA256()
            while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                hash.update(data: data)
            }
            let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == expected.lowercased() else { throw LocalRuntimeFailure.corrupt }
        }
        // Detached не наследует отмену: передаём её явно, чтобы hashing не продолжал читать GGUF.
        try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    private static func availablePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalRuntimeFailure.start }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { throw LocalRuntimeFailure.start }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { throw LocalRuntimeFailure.start }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
