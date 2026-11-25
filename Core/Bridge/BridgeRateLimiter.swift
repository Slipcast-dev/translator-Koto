import Foundation

/// Скользящее окно на весь мост. Токен моста читает любая программа того же пользователя,
/// поэтому лимит ограничивает расход облачной квоты и ресурсов локальной модели.
/// Значения выше обычной работы расширения, включая перевод при прокрутке.
struct BridgeRateLimiter {
    nonisolated static let window: TimeInterval = 60
    let maximumRequests: Int
    let maximumCharacters: Int
    private var events: [(time: TimeInterval, characters: Int)] = []

    init(maximumRequests: Int = 300, maximumCharacters: Int = 150_000) {
        self.maximumRequests = maximumRequests
        self.maximumCharacters = maximumCharacters
    }

    mutating func admit(characters: Int, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        events.removeAll { now - $0.time >= Self.window }
        guard events.count < maximumRequests,
              events.reduce(0, { $0 + $1.characters }) + characters <= maximumCharacters else { return false }
        events.append((now, characters))
        return true
    }
}
