import Foundation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Кэш с вытеснением давно не использованных записей: полная очистка заставляла
/// переводить заново всё, что уже было на экране.
struct RecentCache {
    private var values: [String: (value: String, used: UInt64)] = [:]
    private var clock: UInt64 = 0
    let capacity: Int
    init(capacity: Int) { self.capacity = max(4, capacity) }
    var count: Int { values.count }
    mutating func value(_ key: String) -> String? {
        guard var entry = values[key] else { return nil }
        clock += 1; entry.used = clock; values[key] = entry
        return entry.value
    }
    mutating func store(_ value: String, for key: String) {
        clock += 1
        values[key] = (value, clock)
        guard values.count > capacity else { return }
        // Вытесняется четверть разом, чтобы не сортировать кэш на каждой вставке.
        for item in values.sorted(by: { $0.value.used < $1.value.used }).prefix(capacity / 4) { values[item.key] = nil }
    }
}

/// Быстрый перевод коротких фрагментов с кэшем. Не показывает UI и не пишет текст на диск.
/// Вызывает движок напрямую: после `cancel()` или отмены задачи новые запросы не создаются.
@MainActor
final class QuickTranslator {
    enum Outcome: Equatable {
        case text(String), failure(String)
        /// Остановка пользователем: результат не показывается и запрос не повторяется.
        case cancelled
    }
    private let engine: any TranslationEngine
    private var cache = RecentCache(capacity: 800)
    private var catalog: [TranslationLanguage] = []
    private var catalogEngine = ""
    private var generation = UUID()

    init(engine: any TranslationEngine) { self.engine = engine }

    var languageIDs: [String] { catalog.map(\.id) }

    func loadLanguages() async {
        // Движок могли сменить при закрытом окне Live: каталог принадлежит конкретному движку.
        let name = engine.displayName
        guard catalog.isEmpty || catalogEngine != name, let loaded = try? await engine.supportedLanguages() else { return }
        catalog = loaded
        catalogEngine = name
    }

    /// Вызывается синхронно из stop(): отменяет выполняющийся запрос и запрещает продолжение цикла.
    func cancel() {
        generation = UUID()
        engine.cancel()
    }

    /// Выбор другого движка меняет каталог языков и качество: прежние ответы не переиспользуются.
    func reset() {
        cancel()
        cache = RecentCache(capacity: 800)
        catalog = []
    }

    private func key(_ text: String, _ pair: (source: String, target: String)) -> String {
        "\(engine.displayName)|\(pair.source)|\(pair.target)|\(text)"
    }

    func cached(_ text: String, pair: (source: String, target: String)) -> String? {
        cache.value(key(text, pair))
    }

    /// Несколько строк одним запросом. Построчный повтор нужен только тогда, когда ответ получен,
    /// но число строк не совпало; после ошибки сети или квоты он умножил бы неудачные запросы.
    func translateBatch(_ texts: [String], pair: (source: String, target: String)) async -> [Outcome] {
        let started = generation
        if texts.count > 1 {
            switch await translate(texts.joined(separator: "\n"), pair: pair, remember: false) {
            case .cancelled: return texts.map { _ in .cancelled }
            case .failure(let message): return texts.map { _ in .failure(message) }
            case .text(let joined):
                let parts = joined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                if parts.count == texts.count, parts.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    for (text, part) in zip(texts, parts) { cache.store(part, for: key(text, pair)) }
                    return parts.map { .text($0) }
                }
            }
        }
        var each: [Outcome] = []
        for text in texts {
            guard generation == started, !Task.isCancelled else {
                each.append(.cancelled); continue
            }
            each.append(await translate(text, pair: pair))
        }
        return each
    }

    func translate(_ text: String, pair: (source: String, target: String), remember: Bool = true) async -> Outcome {
        let started = generation
        func stopped() -> Bool { generation != started || Task.isCancelled }
        if let cached = cached(text, pair: pair) { return .text(cached) }
        await loadLanguages()
        guard !stopped() else { return .cancelled }
        guard let target = catalog.first(where: { $0.id == pair.target }) else {
            return .failure(TranslationFailure.serviceUnavailable.errorDescription ?? "")
        }
        var lastFailure = TranslationFailure.failed
        // Короткое слово без признаков языка при автоопределении пробуется как английское.
        for source in pair.source == "auto" ? ["auto", "en"] : [pair.source] {
            let selected = source == "auto" ? nil : catalog.first(where: { $0.id == source })
            if source != "auto", selected == nil { lastFailure = .unsupportedPair; break }
            let limit = engine.requestTimeout
            let began = ContinuousClock.now
            let deadline = Task { [engine] in
                do { try await Task.sleep(for: limit) } catch { return }
                engine.cancel()
            }
            defer { deadline.cancel() }
            do {
                let request = try TranslationRequest(text: text, source: selected, target: target, context: .live)
                let readiness = try await engine.readiness(for: request)
                guard !stopped() else { return .cancelled }
                guard case .installed(let resolved) = readiness else {
                    return .failure(String(localized: "Language not downloaded. Prepare it in the main Koto window first."))
                }
                let result = try await engine.translate(resolved)
                guard !stopped() else { return .cancelled }
                if !result.text.isEmpty {
                    if remember { cache.store(result.text, for: key(text, pair)) }
                    return .text(result.text)
                }
                lastFailure = .failed
                break
            } catch {
                guard !stopped() else { return .cancelled }
                if began.duration(to: .now) >= limit { lastFailure = .timedOut; break }
                lastFailure = (error as? TranslationFailure) ?? .failed
                if lastFailure != .unableToIdentify { break }
            }
        }
        return .failure(lastFailure.errorDescription ?? String(localized: "Unable to translate."))
    }
}
