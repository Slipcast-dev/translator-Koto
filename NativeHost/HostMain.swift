import Foundation
import Darwin

/// Native Messaging host использует один poll-loop: частичный stdin не блокирует socket/stdout.
/// Никаких пользовательских данных в stderr; stdout содержит только framed JSON.
@main
struct KotoNativeHost {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        guard CommandLine.arguments.dropFirst().first == BridgeOrigin.allowed else { exit(64) }
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("Koto native host: protocol or transport failure\n".utf8))
            exit(2)
        }
    }

    private static func run() throws {
        let directory: URL
        if let test = ProcessInfo.processInfo.environment["KOTO_BRIDGE_DIRECTORY"] {
            directory = URL(fileURLWithPath: test, isDirectory: true)
        } else { directory = try PrivateStorage.bridgeDirectory() }
        let socketPath = directory.appendingPathComponent("bridge.sock").path
        let tokenPath = directory.appendingPathComponent("bridge.token")
        for fd in [STDIN_FILENO, STDOUT_FILENO] { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }
        var browserDecoder = BridgeFrameDecoder(), desktopDecoder = BridgeFrameDecoder()
        var socketFD: Int32 = -1
        defer { if socketFD >= 0 { close(socketFD) } }
        var authenticated = false
        var handshakeID: String?
        var toDesktop = Data(), toBrowser = Data()
        var waiting: [BridgeEnvelope] = []
        var pending = Set<String>()
        var connectDeadline = 0.0, retryAt = 0.0, connectedAt = 0.0
        var lastWriteProgress = ProcessInfo.processInfo.systemUptime
        var lastActivity = lastWriteProgress
        var launched = false
        var partialSince: Double?
        let maximumQueue = 4_194_304

        func response(_ id: String, code: String) throws -> Data {
            try BridgeFrameDecoder.encode(BridgeEnvelope(id: id, type: .error, payload: ["code":code]))
        }
        func flush(_ fd: Int32, _ data: inout Data) throws {
            guard !data.isEmpty else { return }
            let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written > 0 { data.removeFirst(written); if fd == STDOUT_FILENO { lastWriteProgress = ProcessInfo.processInfo.systemUptime } }
            else if written < 0 && errno != EAGAIN && errno != EINTR { throw BridgeProtocolFailure.truncated }
        }
        func enqueueBrowser(_ data: Data) {
            // Дедлайн относится только к непустой очереди, а не к простою host.
            // Иначе первый ответ после долгого перевода или паузы ошибочно
            // считается зависшей записью ещё до первой попытки flush.
            if toBrowser.isEmpty { lastWriteProgress = ProcessInfo.processInfo.systemUptime }
            toBrowser.append(data)
        }
        func failPending() throws {
            for id in pending { enqueueBrowser(try response(id, code: "connection_lost")) }
            pending.removeAll(); waiting.removeAll(); toDesktop.removeAll()
        }

        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastActivity > 300 { return }
            if let partialSince, now - partialSince > 10 { throw BridgeProtocolFailure.truncated }
            guard toBrowser.count <= maximumQueue, toDesktop.count <= maximumQueue else { throw BridgeProtocolFailure.length }
            if !toBrowser.isEmpty && now - lastWriteProgress > 15 { throw BridgeProtocolFailure.truncated }
            if socketFD < 0 && !waiting.isEmpty && now >= retryAt {
                if connectDeadline == 0 { connectDeadline = now + 15 }
                if now > connectDeadline { try failPending(); connectDeadline = 0 }
                else {
                    do {
                        var metadata = stat()
                        guard lstat(socketPath, &metadata) == 0, metadata.st_uid == getuid(),
                              (metadata.st_mode & S_IFMT) == S_IFSOCK else { throw CocoaError(.fileReadNoPermission) }
                        let keyData = try PrivateStorage.read(tokenPath, maximum: 128)
                        guard let token = String(data: keyData, encoding: .utf8),
                              Data(base64Encoded: token)?.count == 32 else { throw BridgeProtocolFailure.identity }
                        socketFD = try connectUnix(socketPath)
                        let hello = BridgeEnvelope(type: .hello, payload: ["token":token, "origin":BridgeOrigin.allowed])
                        handshakeID = hello.id
                        toDesktop = try BridgeFrameDecoder.encode(hello)
                        authenticated = false
                        connectedAt = now
                        desktopDecoder = BridgeFrameDecoder()
                    } catch {
                        if socketFD >= 0 { close(socketFD); socketFD = -1 }
                        retryAt = now + 0.4
                        if !launched && ProcessInfo.processInfo.environment["KOTO_BRIDGE_DIRECTORY"] == nil {
                            launched = true
                            launchDesktop()
                        }
                    }
                }
            }
            if socketFD >= 0 && !authenticated && now - connectedAt > 10 {
                close(socketFD); socketFD = -1; try failPending()
            }
            var descriptors = [
                pollfd(fd: STDIN_FILENO, events: pending.count < 16 ? Int16(POLLIN) : 0, revents: 0),
                pollfd(fd: STDOUT_FILENO, events: toBrowser.isEmpty ? 0 : Int16(POLLOUT), revents: 0),
                pollfd(fd: socketFD, events: Int16(POLLIN) | (toDesktop.isEmpty ? 0 : Int16(POLLOUT)), revents: 0)
            ]
            let result = poll(&descriptors, nfds_t(descriptors.count), 50)
            if result < 0 { if errno == EINTR { continue }; throw BridgeProtocolFailure.truncated }
            if descriptors[0].revents & Int16(POLLIN | POLLHUP) != 0 {
                var bytes = [UInt8](repeating: 0, count: 65_536)
                let count = bytes.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count) }
                if count == 0 { try browserDecoder.finish(); return }
                if count > 0 {
                    lastActivity = now
                    for frame in try browserDecoder.append(Data(bytes.prefix(count))) {
                        guard [.translate, .ping, .cancel].contains(frame.type) else { throw BridgeProtocolFailure.identity }
                        guard !pending.contains(frame.id), pending.count < 16 else { throw BridgeProtocolFailure.length }
                        pending.insert(frame.id)
                        if authenticated { toDesktop.append(try BridgeFrameDecoder.encode(frame)) }
                        else { waiting.append(frame) }
                    }
                    if browserDecoder.hasPartialFrame { if partialSince == nil { partialSince = now } }
                    else { partialSince = nil }
                } else if errno != EAGAIN && errno != EINTR { throw BridgeProtocolFailure.truncated }
            }
            if descriptors[1].revents & Int16(POLLOUT) != 0 { try flush(STDOUT_FILENO, &toBrowser) }
            if socketFD >= 0 && descriptors[2].revents & Int16(POLLOUT) != 0 {
                var code: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &code, &length) == 0, code == 0 else {
                    close(socketFD); socketFD = -1; try failPending(); continue
                }
                try flush(socketFD, &toDesktop)
            }
            if socketFD >= 0 && descriptors[2].revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 {
                var bytes = [UInt8](repeating: 0, count: 65_536)
                let count = bytes.withUnsafeMutableBytes { Darwin.read(socketFD, $0.baseAddress, $0.count) }
                if count == 0 {
                    try desktopDecoder.finish()
                    close(socketFD); socketFD = -1
                    authenticated = false
                    try failPending()
                } else if count > 0 {
                    lastActivity = now
                    for frame in try desktopDecoder.append(Data(bytes.prefix(count))) {
                        if !authenticated {
                            guard frame.type == .helloAck, frame.id == handshakeID,
                                  frame.payload["authenticated"] == "true" else { throw BridgeProtocolFailure.identity }
                            authenticated = true
                            connectDeadline = 0
                            for queued in waiting { toDesktop.append(try BridgeFrameDecoder.encode(queued)) }
                            waiting.removeAll()
                        } else {
                            guard pending.remove(frame.id) != nil else { throw BridgeProtocolFailure.identity }
                            guard [.translated, .pong, .error].contains(frame.type) else { throw BridgeProtocolFailure.identity }
                            enqueueBrowser(try BridgeFrameDecoder.encode(frame))
                        }
                    }
                } else if errno != EAGAIN && errno != EINTR { throw BridgeProtocolFailure.truncated }
            }
        }
    }

    private static func connectUnix(_ path: String) throws -> Int32 {
        var address = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw BridgeProtocolFailure.length }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeProtocolFailure.truncated }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 || errno == EINPROGRESS else { close(fd); throw BridgeProtocolFailure.truncated }
        return fd
    }

    private static func launchDesktop() {
        var candidate = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        while candidate.path != "/" && candidate.pathExtension != "app" { candidate.deleteLastPathComponent() }
        guard candidate.pathExtension == "app",
              Bundle(url: candidate)?.bundleIdentifier == "dev.slipcast.koto" else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", candidate.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
