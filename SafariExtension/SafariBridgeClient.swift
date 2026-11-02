import CryptoKit
import Darwin
import Foundation

/// Клиент моста Koto для расширения Safari.
/// Расширение работает в песочнице, где домашний каталог — контейнер, поэтому пути вычисляются
/// от настоящего домашнего каталога пользователя и повторяют PrivateStorage.bridgeSocketPath.
enum SafariBridgeClient {
    struct Failure: Error { let code: String }

    static func realHome() -> String {
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir { return String(cString: home) }
        return NSHomeDirectory()
    }

    static func defaultDirectory() -> String {
        realHome() + "/Library/Application Support/dev.slipcast.koto/BrowserBridge"
    }

    /// Тот же выбор, что у приложения: обычный путь, а слишком длинный переносится в /tmp.
    static func socketPath(directory: String) -> String {
        let ordinary = directory + "/bridge.sock"
        if ordinary.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) { return ordinary }
        let standardized = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL.path
        let digest = SHA256.hash(data: Data(standardized.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
        return "/tmp/koto-bridge-\(getuid())-\(digest)/bridge.sock"
    }

    /// Блокирующий вызов: вызывается из фоновой очереди обработчика, не из потока Safari.
    static func translate(text: String, source: String, target: String, pageOrigin: String,
                          directory: String = defaultDirectory(), timeout: TimeInterval = 240,
                          launchApp: (() -> Void)? = nil) throws -> String {
        guard text.count <= 20_000, !text.isEmpty else { throw Failure(code: "invalid_request") }
        let deadline = Date().addingTimeInterval(timeout)
        let socketFile = socketPath(directory: directory)
        let fd = try connect(socketFile, directory: directory, deadline: deadline, launchApp: launchApp)
        defer { close(fd) }

        let tokenData = try readToken(directory + "/bridge.token")
        var decoder = BridgeFrameDecoder()
        let hello = BridgeEnvelope(type: .hello, payload: ["token": tokenData, "origin": BridgeOrigin.safari])
        try send(fd, hello, deadline: deadline)
        let ack = try receive(fd, &decoder, deadline: deadline) { $0.id == hello.id }
        guard ack.type == .helloAck else { throw Failure(code: "bridge_error") }

        let request = BridgeEnvelope(type: .translate, payload: [
            "text": text, "source": source, "target": target, "pageOrigin": pageOrigin])
        try send(fd, request, deadline: deadline)
        let answer = try receive(fd, &decoder, deadline: deadline) { $0.id == request.id }
        if answer.type == .translated, let translated = answer.payload["text"] { return translated }
        throw Failure(code: answer.payload["code"] ?? "bridge_error")
    }

    private static func readToken(_ path: String) throws -> String {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure(code: "native_host_unavailable") }
        defer { close(fd) }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_uid == getuid(), (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_mode & 0o077 == 0, metadata.st_size > 0, metadata.st_size <= 128 else {
            throw Failure(code: "native_host_unavailable")
        }
        var bytes = [UInt8](repeating: 0, count: 128)
        let count = read(fd, &bytes, bytes.count)
        guard count > 0, let token = String(bytes: bytes.prefix(count), encoding: .utf8),
              Data(base64Encoded: token)?.count == 32 else { throw Failure(code: "native_host_unavailable") }
        return token
    }

    /// Если приложение не запущено, один раз просим систему открыть его и ждём сокет не дольше 20 секунд.
    private static func connect(_ path: String, directory: String, deadline: Date, launchApp: (() -> Void)?) throws -> Int32 {
        var launched = false
        let limit = min(deadline, Date().addingTimeInterval(20))
        while true {
            var metadata = stat()
            if lstat(path, &metadata) == 0, metadata.st_uid == getuid(), (metadata.st_mode & S_IFMT) == S_IFSOCK,
               let fd = try? openSocket(path) { return fd }
            if !launched { launched = true; launchApp?() }
            guard Date() < limit else { throw Failure(code: "native_host_unavailable") }
            usleep(300_000)
        }
    }

    private static func openSocket(_ path: String) throws -> Int32 {
        var address = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw Failure(code: "bridge_error") }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(code: "bridge_error") }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { close(fd); throw Failure(code: "native_host_unavailable") }
        // Как и в native host: подключаться разрешено только к серверу того же пользователя.
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { close(fd); throw Failure(code: "native_host_unavailable") }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    private static func wait(_ fd: Int32, _ events: Int16, deadline: Date) throws {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw Failure(code: "timeout") }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(remaining, 0.25) * 1000))
            if result > 0 { return }
            if result < 0 && errno != EINTR { throw Failure(code: "connection_lost") }
        }
    }

    private static func send(_ fd: Int32, _ envelope: BridgeEnvelope, deadline: Date) throws {
        let frame = try BridgeFrameDecoder.encode(envelope)
        var offset = 0
        while offset < frame.count {
            try wait(fd, Int16(POLLOUT), deadline: deadline)
            let written = frame.withUnsafeBytes { write(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if written < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard written > 0 else { throw Failure(code: "connection_lost") }
            offset += written
        }
    }

    private static func receive(_ fd: Int32, _ decoder: inout BridgeFrameDecoder, deadline: Date,
                                matching: (BridgeEnvelope) -> Bool) throws -> BridgeEnvelope {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            try wait(fd, Int16(POLLIN), deadline: deadline)
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard count > 0 else { throw Failure(code: "connection_lost") }
            let frames = try decoder.append(Data(buffer.prefix(count)))
            if let match = frames.first(where: matching) { return match }
        }
    }
}
