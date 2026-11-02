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
    @ObservationIgnored private var idleStop: Task<Void, Never>?
    /// Модель занимает несколько GB памяти; без запросов runtime выгружается и стартует заново по требованию.
    @ObservationIgnored private let idleTimeout: Duration
    @ObservationIgnored private var privateDirectory: URL?
    @ObservationIgnored private let resourceRoot: URL
    @ObservationIgnored private let modelFileOverride: URL?

    init(resourceRoot: URL? = nil, modelFile: URL? = nil, idleTimeout: Duration = .seconds(600)) {
        self.modelFileOverride = modelFile
        self.idleTimeout = idleTimeout
        self.resourceRoot = resourceRoot ?? Bundle.main.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
    }

    func start() async throws -> LocalEndpoint {
        if let starting { return try await starting.value }
        if let endpoint, process?.isRunning == true { scheduleIdleStop(); return endpoint }
        let id = UUID()
        generation = id
        let task = Task { try await launch(id: id) }
        starting = task
        defer { if generation == id { starting = nil } }
        let ready = try await task.value
        if generation == id { scheduleIdleStop() }
        return ready
    }

    /// Каждый запрос к runtime проходит через start(), поэтому он же продлевает время жизни процесса.
    private func scheduleIdleStop() {
        idleStop?.cancel()
        let current = generation
        let timeout = idleTimeout
        idleStop = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.generation == current, self.isRunning else { return }
            self.stop()
        }
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
            // llama-server читает именно проверенный inode, а не повторно открывает
            // пользовательский путь, который мог измениться после SHA-256.
            let modelSnapshot = try await Self.modelSnapshot(model, expected: spec.sha256, expectedBytes: spec.bytes)
            defer { try? modelSnapshot.close() }
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
            Self.removeStaleDirectories(except: directory)
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
            child.arguments = [runtime.path, "--model", "/dev/fd/0",
                "--host", directory.appendingPathComponent("runtime.sock").path,
                "--api-key-file", keyFile.path, "--ctx-size", "4096",
                "--parallel", "1", "--threads", "4", "--n-gpu-layers", "99",
                "--no-webui", "--offline", "--log-disable"]
            // Исключаем унаследованные LLAMA_* и proxy настройки внешнего окружения.
            child.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(),
                                 "TMPDIR": FileManager.default.temporaryDirectory.path]
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            // Process передаёт handle как stdin; launcher наследует fd 0 через exec.
            // Снимок анонимный: исходный путь и даже содержимое исходного inode
            // больше не влияют на байты, которые откроет llama-server через /dev/fd/0.
            child.standardInput = modelSnapshot
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
            // PID launcher нужен очистке: каталог после краха приложения распознаётся по мёртвому процессу.
            try? Data("\(child.processIdentifier)\n".utf8).write(to: directory.appendingPathComponent("launcher.pid"))
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
        idleStop?.cancel(); idleStop = nil
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
        Self.removeDirectory(directory)
        privateDirectory = nil
    }

    /// Только файлы, которые создаёт launch(); произвольное содержимое каталога не удаляется.
    nonisolated private static func removeDirectory(_ directory: URL) {
        for name in ["api-key", "runtime.sock", "launcher.pid"] { unlink(directory.appendingPathComponent(name).path) }
        rmdir(directory.path)
    }

    /// После краха или принудительного выхода каталог /tmp/koto-<UUID> с ключом остаётся.
    /// Удаляются только свои (uid) каталоги именно такого имени, чей launcher больше не жив:
    /// запущенный другим экземпляром Koto runtime не затрагивается.
    nonisolated static func removeStaleDirectories(except current: URL?) {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for name in names where name.hasPrefix("koto-") && name.dropFirst(5).count == 36 && UUID(uuidString: String(name.dropFirst(5))) != nil {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            if directory.standardizedFileURL == current?.standardizedFileURL { continue }
            var metadata = stat()
            guard lstat(directory.path, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFDIR, metadata.st_uid == getuid() else { continue }
            let pidText = (try? String(contentsOf: directory.appendingPathComponent("launcher.pid"), encoding: .utf8))
                .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            // Без pid-файла каталог принадлежит запуску, не дошедшему до child: безопасно удалить только если он старше минуты.
            if let pidText { if pidText > 1 && kill(pidText, 0) == 0 { continue } }
            else if Date().timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(metadata.st_mtimespec.tv_sec))) < 60 { continue }
            removeDirectory(directory)
        }
    }

    /// Копируем и хешируем одни и те же байты в сразу unlinked tempfile.
    /// Цена защиты от path/in-place TOCTOU — дополнительное временное место размером
    /// с модель. Именованная копия не хранится; отмена/ошибка закрывает оба дескриптора.
    nonisolated static func modelSnapshot(_ source: URL, expected: String, expectedBytes: Int64) async throws -> FileHandle {
        let worker = Task.detached(priority: .utility) {
            let input = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard input >= 0 else { throw LocalRuntimeFailure.missing }
            defer { close(input) }
            var metadata = stat()
            guard fstat(input, &metadata) == 0, metadata.st_uid == getuid(),
                  (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_size == expectedBytes else {
                throw LocalRuntimeFailure.corrupt
            }
            // APFS clone делает снимок за O(1) без записи 2,5 GB на SSD и без двойного места.
            // Клон копирует-при-записи: правка исходного inode после этого его не меняет,
            // поэтому гарантия против in-place TOCTOU сохраняется. Хэш считается по клону.
            if let clone = cloneSnapshot(of: input) {
                var verified = false
                defer { if !verified { close(clone) } }
                var digest = SHA256()
                var total: Int64 = 0
                var buffer = [UInt8](repeating: 0, count: 1_048_576)
                while true {
                    try Task.checkCancellation()
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(clone, $0.baseAddress, $0.count) }
                    if count < 0 && errno == EINTR { continue }
                    guard count >= 0 else { throw LocalRuntimeFailure.corrupt }
                    if count == 0 { break }
                    if total == 0, !buffer.prefix(count).starts(with: Array("GGUF".utf8)) {
                        throw LocalRuntimeFailure.corrupt
                    }
                    total += Int64(count)
                    guard total <= expectedBytes else { throw LocalRuntimeFailure.corrupt }
                    digest.update(data: buffer.prefix(count))
                }
                let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
                guard total == expectedBytes, actual == expected.lowercased(), lseek(clone, 0, SEEK_SET) == 0 else {
                    throw LocalRuntimeFailure.corrupt
                }
                verified = true
                return FileHandle(fileDescriptor: clone, closeOnDealloc: true)
            }
            // Клон недоступен (другой том, не APFS): прежний путь с полной копией.
            var pattern = Array("/tmp/koto-model-XXXXXX".utf8CString)
            let output = mkstemp(&pattern)
            guard output >= 0 else { throw LocalRuntimeFailure.start }
            var transferred = false
            defer { if !transferred { close(output) } }
            // Удаляем имя до записи содержимого: файл доступен только через открытый fd.
            guard pattern.withUnsafeBufferPointer({ unlink($0.baseAddress!) }) == 0 else {
                throw LocalRuntimeFailure.start
            }
            var digest = SHA256()
            var buffer = [UInt8](repeating: 0, count: 1_048_576)
            var total: Int64 = 0
            while true {
                try Task.checkCancellation()
                let count = buffer.withUnsafeMutableBytes { Darwin.read(input, $0.baseAddress, $0.count) }
                if count < 0 && errno == EINTR { continue }
                guard count >= 0 else { throw LocalRuntimeFailure.corrupt }
                if count == 0 { break }
                if total == 0, !buffer.prefix(count).starts(with: Array("GGUF".utf8)) {
                    throw LocalRuntimeFailure.corrupt
                }
                total += Int64(count)
                guard total <= expectedBytes else { throw LocalRuntimeFailure.corrupt }
                let bytes = Data(buffer.prefix(count))
                digest.update(data: bytes)
                var offset = 0
                while offset < count {
                    try Task.checkCancellation()
                    let written = bytes.withUnsafeBytes {
                        Darwin.write(output, $0.baseAddress!.advanced(by: offset), count - offset)
                    }
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw LocalRuntimeFailure.start }
                    offset += written
                }
            }
            let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard total == expectedBytes, actual == expected.lowercased(), lseek(output, 0, SEEK_SET) == 0 else {
                throw LocalRuntimeFailure.corrupt
            }
            transferred = true
            return FileHandle(fileDescriptor: output, closeOnDealloc: true)
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    /// Клонирует открытый inode в приватный каталог и сразу убирает имя: остаётся только fd.
    /// nil означает, что клонирование не поддержано, и вызывающий использует обычную копию.
    nonisolated private static func cloneSnapshot(of input: Int32) -> Int32? {
        var template = Array("/tmp/koto-model-XXXXXX".utf8CString)
        guard let directory = template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress!) }) else { return nil }
        let directoryPath = String(cString: directory)
        let target = directoryPath + "/model"
        defer { unlink(target); rmdir(directoryPath) }
        guard fclonefileat(input, AT_FDCWD, target, 0) == 0 else { return nil }
        let fd = open(target, O_RDONLY | O_NOFOLLOW)
        return fd >= 0 ? fd : nil
    }

    nonisolated static func verifyFile(_ url: URL, expected: String, expectedBytes: Int64? = nil, gguf: Bool = false) async throws {
        let worker = Task.detached(priority: .utility) {
            let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { throw LocalRuntimeFailure.missing }
            let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? file.close() }
            var info = stat()
            // Приложение в /Applications может быть установлено root; проверка hash
            // защищает его содержимое, не требуя пользовательского владения bundle.
            guard fstat(fd, &info) == 0, (info.st_uid == getuid() || info.st_uid == 0),
                  (info.st_mode & S_IFMT) == S_IFREG else {
                throw LocalRuntimeFailure.corrupt
            }
            if let expectedBytes, info.st_size != expectedBytes { throw LocalRuntimeFailure.corrupt }
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
