import Foundation

/// Контекст устанавливает вызывающий модуль, а не текст пользователя или ответ модели.
enum TranslationContext: String, Sendable { case manual, capture, browser, live }

enum TranslationPrivacy {
    /// Начальные исключения не заменяют явный пользовательский список и не претендуют
    /// на полноту: банковские и корпоративные домены пользователь добавляет в Settings.
    static let defaultExcludedHosts = "mail.google.com\noutlook.live.com\noutlook.office.com\nmail.yahoo.com\nmail.yandex.ru\nmail.ru\nproton.me\nprotonmail.com\npaypal.com\nonline.sberbank.ru"

    static func cloudAllowed(_ context: TranslationContext) -> Bool {
        context == .manual || UserDefaults.standard.bool(forKey: "privacy.cloud." + context.rawValue)
    }
    static func browserOriginAllowed(_ value: String, defaults: UserDefaults = .standard) -> Bool {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let rawHost = url.host?.lowercased(), !rawHost.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { return false }
        // DNS допускает абсолютный hostname с конечной точкой; исключения должны
        // одинаково блокировать обычное имя, абсолютное имя и его поддомены.
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty else { return false }
        let blocked = defaults.string(forKey: "privacy.excludedHosts") ?? defaultExcludedHosts
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
