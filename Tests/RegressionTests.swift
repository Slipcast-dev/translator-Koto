import AppKit
import Carbon
import CryptoKit
import Foundation

/// Регрессии аудита и новые функции. Только временные каталоги и отдельные UserDefaults suite.
@main
struct RegressionTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    @MainActor static var passed = 0
    @MainActor static func check(_ condition: Bool, _ name: String) throws {
        guard condition else { throw Failure(description: "FAILED: " + name) }
        passed += 1
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("koto-regression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try damagedStorage(root)
        try glossaryExchange(root)
        try protectedFragments()
        try frameFingerprint()
        try await quickTranslator()
        try await inferenceGate()
        try hotkeys()
        try bridgeLimits()
        try updateHardening()
        try await updateRollback(root)
        print("{\"status\":\"passed\",\"checks\":\(passed)}")
    }

    @MainActor static func defaults() -> UserDefaults { UserDefaults(suiteName: "koto.tests.regression." + UUID().uuidString)! }
    static func names(_ directory: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted() }

    @MainActor static func damagedStorage(_ root: URL) throws {
        let directory = root.appendingPathComponent("store")
        let store = defaults(); store.set(true, forKey: "memory.enabled")
        let first = TranslationStore(directory: directory, defaults: store)
        for index in 0..<3 { first.add(input: "phrase\(index)", output: "x", source: "en", target: "ru") }
        let glossary = directory.appendingPathComponent("glossary.json")
        let original = try Data(contentsOf: glossary)
        // Права 0644 после восстановления из копии: файл не читается, но данные целы.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: glossary.path)
        let reopened = TranslationStore(directory: directory, defaults: store)
        try check(reopened.glossary.isEmpty && !reopened.status.isEmpty, "unreadable glossary is reported")
        try check(!names(directory).contains { $0.contains("corrupt") }, "nothing is moved before a write")
        reopened.add(input: "new", output: "y", source: "en", target: "ru")
        let backup = names(directory).first { $0.hasPrefix("glossary.json.corrupt-") }
        try check(backup != nil, "damaged file kept as a backup before the first write")
        try check(try Data(contentsOf: directory.appendingPathComponent(backup ?? "")) == original, "backup keeps every old phrase")

        // Повреждённый словарь не мешает читать память, а очистка памяти удаляет и её копии.
        let memory = directory.appendingPathComponent("memory.json")
        try PrivateStorage.write(JSONEncoder().encode([PhraseRecord(input: "a", output: "b", source: "en", target: "ru")]), to: memory)
        try PrivateStorage.write(Data("broken".utf8), to: glossary)
        try check(TranslationStore(directory: directory, defaults: store).memory.count == 1, "memory loads despite a damaged glossary")
        try PrivateStorage.write(Data("private broken text".utf8), to: memory)
        let damagedMemory = TranslationStore(directory: directory, defaults: store)
        let request = try TranslationRequest(text: "hello", source: TranslationLanguage(id: "en"), target: TranslationLanguage(id: "ru"))
        damagedMemory.remember(request, result: TranslationResult(requestID: request.id, text: "привет",
            source: TranslationLanguage(id: "en"), target: TranslationLanguage(id: "ru")))
        damagedMemory.flush()
        try check(names(directory).contains { $0.hasPrefix("memory.json.corrupt-") }, "damaged memory preserved before overwrite")
        damagedMemory.clearMemory()
        try check(!names(directory).contains { $0.hasPrefix("memory.json.corrupt-") }, "clearing memory removes its backups")
    }

    @MainActor static func glossaryExchange(_ root: URL) throws {
        let source = TranslationStore(directory: root.appendingPathComponent("export"), defaults: defaults())
        source.add(input: "comma, \"quote\"\nsecond line", output: "=SUM(A1)", source: "en", target: "ru")
        source.add(input: "'apostrophe", output: "- dash", source: "en", target: "de")
        for format in GlossaryFormat.allCases {
            let data = try source.exportGlossary(format)
            let copy = TranslationStore(directory: root.appendingPathComponent("import-\(format.rawValue)"), defaults: defaults())
            try check(copy.importGlossary(data, format: format), "\(format) import succeeds")
            try check(copy.glossary.map { [$0.input, $0.output, $0.source, $0.target] }
                == source.glossary.map { [$0.input, $0.output, $0.source, $0.target] }, "\(format) round trip is exact")
            try check(copy.importGlossary(data, format: format) && copy.glossary.count == 2, "\(format) reimport does not duplicate")
        }
        let csv = String(decoding: try source.exportGlossary(.csv), as: UTF8.self)
        try check(csv.contains("\"'=SUM(A1)\""), "spreadsheet formulas are neutralised on export")
        let plain = "source,target,input,output\nen,ru,hello,привет\n"
        try check(source.importGlossary(Data(("\u{FEFF}" + plain).utf8), format: .csv), "hand written CSV with BOM and LF accepted")
        let before = source.glossary.count
        for (bad, format) in [("source,target,input,output\nen,ru,ok,да\nen,en,same,pair\n", GlossaryFormat.csv),
                              ("source,target,input,output\nen,ru,\"unterminated,x\n", .csv),
                              ("wrong,header\n", .csv), ("{\"schema\":2,\"phrases\":[]}", .json), ("not json", .json)] {
            try check(!source.importGlossary(Data(bad.utf8), format: format) && source.glossary.count == before, "invalid file rejected atomically")
        }
        let many = "source,target,input,output\n" + (0..<201).map { "en,ru,w\($0),x\n" }.joined()
        try check(!source.importGlossary(Data(many.utf8), format: .csv) && source.glossary.count == before, "phrase limit enforced")
    }

    @MainActor static func protectedFragments() throws {
        for (input, output) in [("Visit https://example.com.", "请访问 https://example.com。"),
                                ("See https://example.com, then go", "Смотрите https://example.com — затем идите"),
                                ("见https://example.com。然后", "See https://example.com then")] {
            try check(TranslationChunker.preservesProtectedFragments(source: input, output: output), "punctuation after URL may change: \(output)")
        }
        try check(!TranslationChunker.preservesProtectedFragments(source: "Open https://example.com/a?b=1.", output: "Откройте https://example.com/a."), "changed URL still rejected")
        try check(!TranslationChunker.preservesProtectedFragments(source: "Hi {name}.", output: "Привет."), "lost placeholder still rejected")
    }

    static func frame(_ subtitle: String, _ width: Int, _ height: Int, caret: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (subtitle as NSString).draw(at: CGPoint(x: width / 4, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.white])
        if caret { context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 40, y: height - 80, width: 2, height: 20)) }
        NSGraphicsContext.current = nil
        return context.makeImage()!
    }

    @MainActor static func frameFingerprint() throws {
        for (width, height) in [(800, 200), (1280, 720), (1920, 1080), (2560, 1440), (4096, 2304)] {
            let first = FrameFingerprint.make(from: frame("I will never go back there again.", width, height))!
            let same = FrameFingerprint.make(from: frame("I will never go back there again.", width, height))!
            let caret = FrameFingerprint.make(from: frame("I will never go back there again.", width, height, caret: true))!
            let next = FrameFingerprint.make(from: frame("She told me the meeting is tomorrow.", width, height))!
            try check(first.matches(same), "identical frame skipped \(width)x\(height)")
            try check(first.matches(caret), "blinking caret skipped \(width)x\(height)")
            try check(!first.matches(next), "new subtitle detected \(width)x\(height)")
        }
    }

    @MainActor final class StubEngine: TranslationEngine {
        var sent: [String] = []
        var reply: (String) throws -> String = { "t:" + $0 }
        var delay = Duration.zero
        var displayName: String { "stub" }
        func supportedLanguages() async throws -> [TranslationLanguage] { ["en", "ru"].map { TranslationLanguage(id: $0) } }
        func readiness(for request: TranslationRequest) async throws -> TranslationReadiness { .installed(request) }
        func translate(_ request: TranslationRequest) async throws -> TranslationResult {
            sent.append(request.text)
            // try? имитирует движок, который доводит запрос до конца несмотря на отмену.
            try? await Task.sleep(for: delay)
            return TranslationResult(requestID: request.id, text: try reply(request.text),
                source: request.source ?? TranslationLanguage(id: "en"), target: request.target)
        }
        func cancel() {}
    }

    @MainActor static func quickTranslator() async throws {
        let pair = (source: "en", target: "ru")
        let lines = (1...12).map { "line\($0)" }
        for useCancel in [true, false] {
            let engine = StubEngine(); engine.delay = .milliseconds(200)
            let translator = QuickTranslator(engine: engine)
            let task = Task { await translator.translateBatch(lines, pair: pair) }
            try await Task.sleep(for: .milliseconds(60))
            if useCancel { translator.cancel() }
            task.cancel()
            let outcomes = await task.value
            try await Task.sleep(for: .milliseconds(400))
            try check(engine.sent.count == 1, "no request is started after Stop (\(engine.sent.count))")
            try check(outcomes.allSatisfy { $0 == .cancelled }, "stopped batch shows nothing")
        }
        let failing = StubEngine(); failing.reply = { _ in throw TranslationFailure.serviceUnavailable }
        let failed = await QuickTranslator(engine: failing).translateBatch(lines, pair: pair)
        try check(failing.sent.count == 1 && failed.count == 12, "a failed batch is not repeated line by line")
        let merging = StubEngine(); merging.reply = { $0.contains("\n") ? "merged" : "ok:" + $0 }
        let translator = QuickTranslator(engine: merging)
        let separate = await translator.translateBatch(["a", "b"], pair: pair)
        try check(separate == [.text("ok:a"), .text("ok:b")] && merging.sent.count == 3, "line count mismatch falls back to single lines")
        _ = await translator.translate("a", pair: pair)
        try check(merging.sent.count == 3, "cached line is not sent again")

        var cache = RecentCache(capacity: 8)
        for index in 0..<8 { cache.store("v", for: "k\(index)") }
        _ = cache.value("k0")
        cache.store("v", for: "k8")
        try check(cache.value("k0") != nil && cache.value("k1") == nil && cache.count <= 8, "cache evicts least recently used entries")
    }

    @MainActor static func inferenceGate() async throws {
        let gate = InferenceGate()
        try await gate.acquire()
        var order: [Int] = []
        func waiter(_ number: Int) -> Task<Void, Never> {
            Task { @MainActor in
                do { try await gate.acquire(); order.append(number); gate.release() } catch { order.append(-number) }
            }
        }
        let second = waiter(2); await Task.yield()
        let third = waiter(3); await Task.yield()
        try await Task.sleep(for: .milliseconds(20))
        try check(gate.waiting == 2 && order.isEmpty, "requests wait for the single model slot")
        second.cancel(); await second.value
        gate.release(); await third.value
        try check(order == [-2, 3], "cancelled waiter leaves the queue, order preserved")
        try await gate.acquire(); gate.release()
        try check(gate.waiting == 0, "slot is free afterwards")
    }

    @MainActor static func hotkeys() throws {
        let store = defaults()
        try check(HotkeyPreferences.load(store) == HotkeyPreferences.defaults, "default shortcuts")
        try check(HotkeyPreferences.defaults[.selection]?.display == "⌃⌥⌘T", "default display")
        var bindings = HotkeyPreferences.defaults
        let custom = HotkeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey), key: "K")
        try check(HotkeyPreferences.problem(custom, for: .live, in: bindings) == nil, "two modifiers accepted")
        bindings[.live] = custom
        HotkeyPreferences.save(bindings, to: store)
        try check(HotkeyPreferences.load(store)[.live] == custom, "custom shortcut persists")
        try check(HotkeyPreferences.problem(custom, for: .region, in: bindings) != nil, "duplicate rejected")
        for modifiers in [0, cmdKey, shiftKey | optionKey] {
            let unsafe = HotkeyBinding(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(modifiers), key: "C")
            try check(!unsafe.isAcceptable, "typing and common shortcuts cannot be captured")
        }
        try check(HotkeyBinding(keyCode: UInt32(kVK_F6), modifiers: UInt32(cmdKey), key: "F6").isAcceptable, "function key with command accepted")
        store.set(Data("garbage".utf8), forKey: HotkeyPreferences.key)
        try check(HotkeyPreferences.load(store) == HotkeyPreferences.defaults, "damaged preference falls back")
        try check(HotkeyBinding.keyName(keyCode: kVK_ANSI_T, characters: "е") == "T", "label does not depend on input language")
    }

    @MainActor static func bridgeLimits() throws {
        var limiter = BridgeRateLimiter(maximumRequests: 3, maximumCharacters: 100)
        try check(limiter.admit(characters: 60, now: 0) && !limiter.admit(characters: 60, now: 1), "character budget")
        try check(limiter.admit(characters: 1, now: 2) && limiter.admit(characters: 1, now: 3) && !limiter.admit(characters: 1, now: 4), "request budget")
        try check(limiter.admit(characters: 90, now: 70), "window slides")
    }

    @MainActor static func updateHardening() throws {
        try check(UpdateCatalog.isSafeAssetName("Koto-2.0.0-22-arm64.dmg"), "release name accepted")
        for name in ["../evil-arm64.dmg", "a/b-arm64.dmg", ".hidden-arm64.dmg", "Koto arm64.dmg", "Koto-arm64.dmg\n"] {
            try check(!UpdateCatalog.isSafeAssetName(name), "unsafe asset name rejected")
        }
        let old = Curve25519.Signing.PrivateKey(), new = Curve25519.Signing.PrivateKey()
        let value = [old, new].map { $0.publicKey.rawRepresentation.base64EncodedString() }.joined(separator: ",")
        try check(UpdateInstaller.publicKeys(from: value)?.count == 64, "two rotation keys parsed")
        try check(UpdateInstaller.publicKeys(from: "bad," + value) == nil && UpdateInstaller.publicKeys(from: "") == nil, "malformed key list rejected")
    }

    /// Настоящий скрипт замены на временных каталогах; вместо /usr/bin/open — подставной запуск.
    @MainActor static func updateRollback(_ root: URL) async throws {
        for launches in [true, false] {
            let work = root.appendingPathComponent("swap-\(launches)")
            let target = work.appendingPathComponent("Koto.app"), staged = work.appendingPathComponent(".staged.app")
            for (directory, content) in [(target, "old"), (staged, "new")] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try content.write(to: directory.appendingPathComponent("version"), atomically: true, encoding: .utf8)
            }
            let opener = work.appendingPathComponent("opener.sh")
            let body = launches ? "touch '\(work.path)/\(UpdateInstaller.launchMarkerName)'" : "true"
            try "#!/bin/sh\n\(body)\n".write(to: opener, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: opener.path)
            let exited = Process(); exited.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            try exited.run(); exited.waitUntilExit()
            try UpdateInstaller.launchSwap(staged: staged, target: target, processID: exited.processIdentifier,
                relaunch: true, workDirectory: work, opener: opener.path, launchTimeoutSeconds: 2)
            for _ in 0..<100 where names(work).contains(where: { $0.hasPrefix("swap-") }) {
                try await Task.sleep(for: .milliseconds(100))
            }
            let version = try String(contentsOf: target.appendingPathComponent("version"), encoding: .utf8)
            try check(version == (launches ? "new" : "old"), launches ? "confirmed update is kept" : "update that never starts is rolled back")
            try check(names(work) == ["Koto.app", "opener.sh"], "no leftovers after swap: \(names(work))")
        }
    }
}
