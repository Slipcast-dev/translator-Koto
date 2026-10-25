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

/// PID принадлежит живому launcher; проверка peer выполняется на каждом соединении.
struct LocalEndpoint: Sendable {
    let socketPath: String
    let launcherPID: pid_t
    let token: String
}

/// HTTP/1.0 по AF_UNIX: один запрос на соединение, без redirects, proxy и повторов.
/// Секрет отправляется только после проверки kernel credentials того же сокета.
enum LocalRuntimeTransport {
    nonisolated static func request(_ endpoint: LocalEndpoint, path: String, body: Data? = nil,
                                    authorized: Bool = true, timeout: TimeInterval = 120) async throws -> (Data, Int) {
        let worker = Task.detached(priority: .userInitiated) {
            try exchange(endpoint, path: path, body: body, authorized: authorized, timeout: timeout)
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    nonisolated private static func exchange(_ endpoint: LocalEndpoint, path: String, body: Data?,
                                             authorized: Bool, timeout: TimeInterval) throws -> (Data, Int) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalRuntimeFailure.start }
        defer { close(fd) }
        var noSignal: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal))) == 0,
              fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw LocalRuntimeFailure.start }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(endpoint.socketPath.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw LocalRuntimeFailure.start }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        func wait(_ events: Int16) throws {
            while true {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw LocalRuntimeFailure.timeout }
                var descriptor = pollfd(fd: fd, events: events, revents: 0)
                let result = poll(&descriptor, 1, 100)
                if result > 0 { return }
                if result < 0 && errno != EINTR { throw LocalRuntimeFailure.stopped }
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS else { throw LocalRuntimeFailure.start }
            try wait(Int16(POLLOUT))
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout.size(ofValue: error))
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
                throw LocalRuntimeFailure.start
            }
        }
        // Проверяем не путь до connect, а реального peer уже установленного соединения.
        // Подменивший .sock процесс того же пользователя не является child нашего launcher.
        var peer: pid_t = 0
        var size = socklen_t(MemoryLayout.size(ofValue: peer))
        var info = proc_bsdinfo()
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard endpoint.launcherPID > 1, getpeereid(fd, &uid, &gid) == 0, uid == getuid(),
              getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peer, &size) == 0,
              proc_pidinfo(peer, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) == Int32(MemoryLayout.size(ofValue: info)),
              info.pbi_ppid == UInt32(endpoint.launcherPID) else { throw LocalRuntimeFailure.corrupt }
        try Task.checkCancellation()
        var headers = "\(body == nil ? "GET" : "POST") \(path) HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n"
        if authorized { headers += "Authorization: Bearer " + endpoint.token + "\r\n" }
        if let body { headers += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n" }
        var outgoing = Data((headers + "\r\n").utf8)
        if let body { outgoing.append(body) }
        var offset = 0
        while offset < outgoing.count {
            try wait(Int16(POLLOUT))
            let written = outgoing.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if written < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard written > 0 else { throw LocalRuntimeFailure.stopped }
            offset += written
        }
        var incoming = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            try wait(Int16(POLLIN))
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard count >= 0 else { throw LocalRuntimeFailure.stopped }
            if count == 0 { break }
            incoming.append(contentsOf: buffer.prefix(count))
            guard incoming.count <= 1_114_112 else { throw LocalRuntimeFailure.corrupt }
        }
        guard let separator = incoming.range(of: Data("\r\n\r\n".utf8)),
              separator.lowerBound <= 65536,
              let header = String(data: incoming[..<separator.lowerBound], encoding: .utf8),
              let line = header.components(separatedBy: "\r\n").first,
              let status = Int(line.split(separator: " ").dropFirst().first ?? ""),
              !header.lowercased().contains("transfer-encoding:") else { throw LocalRuntimeFailure.corrupt }
        let payload = Data(incoming[separator.upperBound...])
        guard payload.count <= 1_048_576 else { throw LocalRuntimeFailure.corrupt }
        // Неполный ответ не выдаётся за успешный JSON после аварийного закрытия child.
        if let lengthLine = header.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }) {
            guard let length = Int(lengthLine.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)),
                  length == payload.count else { throw LocalRuntimeFailure.corrupt }
        }
        return (payload, status)
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

    init(resourceRoot: URL? = nil, modelFile: URL? = nil) {
        self.modelFileOverride = modelFile
        self.resourceRoot = resourceRoot ?? Bundle.main.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
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
            var random = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
                throw LocalRuntimeFailure.start
            }
            let token = Data(random).base64EncodedString()
            // sockaddr_un ограничивает длину пути: пользовательский TMPDIR может быть
            // слишком длинным. mkdir(0700) + случайное имя не допускают чужой готовый каталог.
            let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
                .appendingPathComponent("koto-" + UUID().uuidString, isDirectory: true)
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
            child.arguments = [runtime.path, "--model", model.path,
                "--host", directory.appendingPathComponent("runtime.sock").path,
                "--api-key-file", keyFile.path, "--ctx-size", "4096",
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
            let ready = LocalEndpoint(socketPath: directory.appendingPathComponent("runtime.sock").path,
                                      launcherPID: child.processIdentifier, token: token)
            status = String(localized: "Loading local model…")
            let until = ContinuousClock.now.advanced(by: .seconds(120))
            while ContinuousClock.now < until {
                try Task.checkCancellation()
                guard generation == id, child.isRunning else { throw LocalRuntimeFailure.start }
                if let (_, statusCode) = try? await LocalRuntimeTransport.request(ready, path: "/health", authorized: false, timeout: 2),
                   statusCode == 200 {
                    try Task.checkCancellation()
                    guard generation == id, child.isRunning else { throw LocalRuntimeFailure.start }
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
        unlink(directory.appendingPathComponent("runtime.sock").path)
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
}
