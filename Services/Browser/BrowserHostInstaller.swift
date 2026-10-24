import Foundation
import Darwin

/// Регистрация только собственного host manifest. Расширение не устанавливается скрытно.
enum BrowserHostInstaller {
    static func installForChrome() throws {
        guard let executable = Bundle.main.url(forResource: "koto-native-host", withExtension: nil, subdirectory: "BrowserBridge") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        var directory = root
        for component in ["Google","Chrome","NativeMessagingHosts"] {
            directory.appendPathComponent(component)
            var metadata = stat()
            if lstat(directory.path, &metadata) == 0 {
                guard (metadata.st_mode & S_IFMT) == S_IFDIR, metadata.st_uid == getuid() else {
                    throw CocoaError(.fileWriteNoPermission)
                }
            } else {
                guard errno == ENOENT, mkdir(directory.path, 0o700) == 0 else { throw CocoaError(.fileWriteNoPermission) }
            }
        }
        let manifest: [String: Any] = ["name":"dev.slipcast.koto","description":"Koto — Slipcast-Dev",
            "path":executable.path,"type":"stdio","allowed_origins":[BridgeOrigin.allowed]]
        try PrivateStorage.write(try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]),
                                 to: directory.appendingPathComponent("dev.slipcast.koto.json"))
    }
}
