import Foundation

enum ProductTestError: Error { case assertion(String) }
@main struct ProductPrivacyTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "dev.slipcast.koto.tests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw ProductTestError.assertion("defaults") }
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        var passed: [String] = []
        func expect(_ value: Bool, _ name: String) throws {
            guard value else { throw ProductTestError.assertion(name) }; passed.append(name)
        }
        let store = TranslationStore(directory: directory, defaults: defaults)
        let request = try TranslationRequest(text: "cat",source: TranslationLanguage(id:"en"),target: TranslationLanguage(id:"ru"))
        let result = TranslationResult(requestID:request.id,text:"кот",source:TranslationLanguage(id:"en"),target:request.target)
        store.remember(request,result:result)
        try expect(store.memory.isEmpty && !FileManager.default.fileExists(atPath:directory.appendingPathComponent("memory.json").path),"memory opt-out writes no text")
        store.memoryEnabled = true
        store.remember(request,result:result)
        try expect(store.lookup(request)?.1 == "Память переводов","opt-in memory lookup")
        let restored = TranslationStore(directory:directory,defaults:defaults)
        try expect(restored.memory.count == 1,"memory persists privately")
        store.add(input:"cat",output:"кошка",source:"en",target:"ru")
        try expect(store.lookup(request)?.0.output == "кошка","glossary overrides memory")
        let engine = StoredPhraseEngine(store.glossary[0],title:"Словарь фраз")
        let storedResult = try await engine.translate(request)
        try expect(storedResult.requestID == request.id && storedResult.engineLabel == "Словарь фраз","stored result preserves identity and provenance")
        let live = try TranslationRequest(text:"cat",source:TranslationLanguage(id:"en"),target:request.target,context:.live)
        try expect(try live.resolvingSource(TranslationLanguage(id:"en")).context == .live,"source resolution preserves privacy context")
        store.remove(store.glossary[0].id)
        try expect(store.lookup(live) == nil,"live never reads manual memory")
        store.remember(live,result:result)
        try expect(store.memory.count == 1,"live never writes manual memory")
        store.memoryEnabled = false
        let cleared = TranslationStore(directory:directory,defaults:defaults)
        try expect(cleared.memory.isEmpty && (try JSONDecoder().decode([PhraseRecord].self,from:PrivateStorage.read(directory.appendingPathComponent("memory.json"),maximum:100))) .isEmpty,"disable clears persisted text")
        let modelEngine: any TranslationEngine = engine
        try expect(modelEngine.displayName == "Словарь фраз","existential dispatch reports actual engine")
        let report: [String:Any] = ["status":"passed","count":passed.count,"tests":passed]
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
