import Foundation

/// Контекст устанавливает вызывающий модуль, а не текст пользователя или ответ модели.
enum TranslationContext: String, Sendable { case manual, capture, browser, live }

enum TranslationPrivacy {
    static func cloudAllowed(_ context: TranslationContext) -> Bool {
        context == .manual || UserDefaults.standard.bool(forKey: "privacy.cloud." + context.rawValue)
    }
    static func browserOriginAllowed(_ value: String) -> Bool {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { return false }
        let blocked = UserDefaults.standard.string(forKey: "privacy.excludedHosts") ?? ""
        return !blocked.split(whereSeparator: { $0.isWhitespace || $0 == "," }).contains {
            let suffix = $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return !suffix.isEmpty && (host == suffix || host.hasSuffix("." + suffix))
        }
    }
    static var excludedApplications: Set<String> {
        let stored = UserDefaults.standard.string(forKey: "privacy.excludedApps")
            ?? "com.apple.mail\ncom.apple.MobileSMS\nru.keepcoder.Telegram\nnet.whatsapp.WhatsApp\ncom.viber.osx"
        return Set(stored.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
    }
    static func excluded(_ bundleID: String?) -> Bool { bundleID.map { excludedApplications.contains($0) } ?? false }
}
