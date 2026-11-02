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

    // MARK: Установка и удаление расширения целиком

    private static var hostManifestURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.slipcast.koto.json")
    }

    /// Копия расширения вне bundle: Chrome хранит путь к распакованному расширению, а bundle
    /// при обновлении заменяется целиком. Стабильный каталог переживает перенос и обновление приложения.
    static var extensionDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/dev.slipcast.koto/ChromeExtension", isDirectory: true)
    }

    /// Установлено = host зарегистрирован для этой копии Koto и файлы расширения на месте.
    static var isChromeInstalled: Bool {
        guard let data = try? PrivateStorage.read(hostManifestURL, maximum: 65_536),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["path"] as? String,
              let executable = Bundle.main.url(forResource: "koto-native-host", withExtension: nil, subdirectory: "BrowserBridge"),
              path == executable.path else { return false }
        return FileManager.default.fileExists(atPath: extensionDirectory.appendingPathComponent("manifest.json").path)
    }

    /// Регистрирует host и кладёт файлы расширения в стабильный каталог. Chrome всё равно
    /// требует ручного подтверждения «Загрузить распакованное расширение»: тихая установка невозможна.
    static func installChrome(bundledExtension: URL? = nil) throws {
        guard let source = bundledExtension ?? Bundle.main.url(forResource: "BrowserExtension", withExtension: nil),
              FileManager.default.fileExists(atPath: source.appendingPathComponent("manifest.json").path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try installForChrome()
        let destination = extensionDirectory
        try PrivateStorage.ensureDirectory(destination.deletingLastPathComponent())
        // Копируем рядом и заменяем целиком: Chrome не увидит наполовину записанное расширение.
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".ChromeExtension-" + UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
    }

    /// Удаляет только собственные файлы Koto: host manifest и копию расширения.
    /// Само расширение в chrome://extensions пользователь удаляет в Chrome.
    static func removeChrome() throws {
        let manifest = hostManifestURL
        var metadata = stat()
        if lstat(manifest.path, &metadata) == 0 {
            guard (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_uid == getuid() else {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.removeItem(at: manifest)
        }
        if FileManager.default.fileExists(atPath: extensionDirectory.path) {
            try FileManager.default.removeItem(at: extensionDirectory)
        }
    }
}
