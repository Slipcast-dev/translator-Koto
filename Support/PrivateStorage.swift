import Foundation
import Security
import Darwin

/// Только собственные файлы: O_NOFOLLOW, owner UID, 0700 directory, 0600 regular files.
enum PrivateStorage {
    static func bridgeDirectory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let base = support.appendingPathComponent("dev.slipcast.koto", isDirectory: true)
        try ensureDirectory(base)
        let bridge = base.appendingPathComponent("BrowserBridge", isDirectory: true)
        try ensureDirectory(bridge)
        return bridge
    }
    static func ensureDirectory(_ url: URL) throws {
        var metadata = stat()
        if lstat(url.path, &metadata) == 0 {
            guard (metadata.st_mode & S_IFMT) == S_IFDIR, metadata.st_uid == getuid() else {
                throw CocoaError(.fileWriteNoPermission)
            }
            guard chmod(url.path, 0o700) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        } else {
            guard errno == ENOENT, mkdir(url.path, 0o700) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        }
    }
    static func read(_ url: URL, maximum: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(fd) }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_uid == getuid(),
              (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_mode & 0o077 == 0,
              metadata.st_size >= 0, metadata.st_size <= maximum else { throw CocoaError(.fileReadNoPermission) }
        var result = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count == 0 { break }
            guard count > 0, result.count + count <= maximum else { throw CocoaError(.fileReadCorruptFile) }
            result.append(contentsOf: bytes.prefix(count))
        }
        return result
    }
    static func write(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        var success = false
        defer { close(fd); if !success { unlink(temporary.path) } }
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress?.advanced(by: offset), data.count - offset) }
            guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
            offset += count
        }
        var old = stat()
        if lstat(url.path, &old) == 0 {
            guard (old.st_mode & S_IFMT) == S_IFREG, old.st_uid == getuid() else { throw CocoaError(.fileWriteNoPermission) }
        }
        guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        success = true
    }
    static func token() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        return Data(bytes).base64EncodedString()
    }
    static func matches(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8), b = Array(right.utf8)
        guard a.count == b.count else { return false }
        return zip(a,b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
