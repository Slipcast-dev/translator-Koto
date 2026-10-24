import Foundation

/// Имя автора и версия берутся из bundle, который собирается из Config/Product.xcconfig.
/// Так About и метаданные не получают независимые копии изменяемых сведений.
enum ProductInfo {
    private static func value(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }

    static var name: String { value("CFBundleName") }
    static var developer: String { value("KotoDeveloper") }
    static var version: String { value("CFBundleShortVersionString") }
    static var build: String { value("CFBundleVersion") }
    static var copyright: String { value("NSHumanReadableCopyright") }
    static var versionDescription: String { "Версия \(version) (\(build))" }
}
