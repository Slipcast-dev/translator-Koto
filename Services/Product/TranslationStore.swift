import Foundation
import Observation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

struct PhraseRecord: Codable, Identifiable {
    var id = UUID()
    let input: String
    let output: String
    let source: String
    let target: String
}

/// Словарь — точное совпадение фразы и пары. Память добровольная, ограниченная, без скрытой истории.
@MainActor @Observable
final class TranslationStore {
    static let shared = TranslationStore()
    private let directoryOverride: URL?
    private let defaults: UserDefaults
    private(set) var glossary: [PhraseRecord] = []
    private(set) var memory: [PhraseRecord] = []
    private(set) var status = ""
    var memoryEnabled: Bool {
        didSet {
            defaults.set(memoryEnabled, forKey: "memory.enabled")
            if !memoryEnabled { clearMemory() }
        }
    }
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directoryOverride = directory
        self.defaults = defaults
        memoryEnabled = defaults.bool(forKey: "memory.enabled")
        do {
            glossary = try load("glossary.json", maximum: 200)
            if memoryEnabled { memory = try load("memory.json", maximum: 500) }
        } catch { status = String(localized: "Unable to read local storage. The file was not overwritten.") }
    }
    private func file(_ name: String) throws -> URL {
        if let directoryOverride { try PrivateStorage.ensureDirectory(directoryOverride); return directoryOverride.appendingPathComponent(name) }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let base = support.appendingPathComponent("dev.slipcast.koto", isDirectory: true)
        try PrivateStorage.ensureDirectory(base)
        let dir = base.appendingPathComponent("Phrases", isDirectory: true)
        try PrivateStorage.ensureDirectory(dir)
        return dir.appendingPathComponent(name)
    }
    private func load(_ name: String, maximum: Int) throws -> [PhraseRecord] {
        let url = try file(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let records = try JSONDecoder().decode([PhraseRecord].self, from: PrivateStorage.read(url, maximum: 8_388_608))
        guard records.count <= maximum, records.allSatisfy({ valid($0) }) else { throw CocoaError(.fileReadCorruptFile) }
        return records
    }
    private func valid(_ record: PhraseRecord) -> Bool {
        !record.input.isEmpty && !record.output.isEmpty && record.input.count <= 2000 && record.output.count <= 4000
            && record.source.count <= 32 && record.target.count <= 32
    }
    private func persist(_ records: [PhraseRecord], name: String) throws {
        try PrivateStorage.write(JSONEncoder().encode(records), to: file(name))
    }
    func lookup(_ request: TranslationRequest) -> (PhraseRecord, String)? {
        // Автоопределение не подбирает пользовательскую пару наугад.
        guard let source = request.source?.id else { return nil }
        let match: (PhraseRecord) -> Bool = { $0.input == request.text && $0.source == source && $0.target == request.target.id }
        if let found = glossary.last(where: match) { return (found, String(localized: "Exact phrases")) }
        if memoryEnabled, request.context == .manual, let found = memory.last(where: match) { return (found, String(localized: "Translation memory")) }
        return nil
    }
    func add(input: String, output: String, source: String, target: String) {
        let record = PhraseRecord(input: input, output: output, source: source, target: target)
        guard valid(record), source != target else { status = String(localized: "Check the phrase and choose different languages (up to \(AppLocalization.number(2_000))/\(AppLocalization.number(4_000)) characters)."); return }
        var next = glossary.filter { !($0.input == input && $0.source == source && $0.target == target) }
        guard next.count < 200 else { status = String(localized: "The limit of 200 phrases has been reached."); return }
        next.append(record)
        do { try persist(next, name: "glossary.json"); glossary = next; status = String(localized: "Phrase saved") }
        catch { status = String(localized: "Unable to save exact phrases") }
    }
    func remove(_ id: UUID) {
        let next = glossary.filter { $0.id != id }
        do { try persist(next, name: "glossary.json"); glossary = next }
        catch { status = String(localized: "Unable to remove the phrase") }
    }
    func remember(_ request: TranslationRequest, result: TranslationResult) {
        guard memoryEnabled, request.context == .manual else { return }
        let record = PhraseRecord(input: request.text, output: result.text, source: result.source.id, target: result.target.id)
        guard valid(record) else { return }
        var next = memory.filter { !($0.input == record.input && $0.source == record.source && $0.target == record.target) }
        next.append(record)
        next = Array(next.suffix(500))
        do { try persist(next, name: "memory.json"); memory = next }
        catch { status = String(localized: "Unable to save translation memory") }
    }
    func clearMemory() {
        do { try persist([], name: "memory.json"); memory.removeAll(); status = String(localized: "Memory cleared") }
        catch { status = String(localized: "Unable to clear the memory file") }
    }
}

/// Пользовательские фразы не проходят через облако или языковую модель.
@MainActor
final class StoredPhraseEngine: TranslationEngine {
    let record: PhraseRecord
    let displayName: String
    init(_ record: PhraseRecord, title: String) { self.record = record; displayName = title }
    func supportedLanguages() async throws -> [TranslationLanguage] { [] }
    func readiness(for request: TranslationRequest) async throws -> TranslationReadiness { .installed(request) }
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        TranslationResult(requestID: request.id, text: record.output, source: TranslationLanguage(id: record.source),
                          target: request.target, engineLabel: displayName)
    }
    func cancel() {}
}
