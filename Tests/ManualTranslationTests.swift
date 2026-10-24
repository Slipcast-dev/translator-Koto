import Foundation

enum ManualTestError: Error { case assertion(String) }

/// Управляем только реальной внешней границей engine. Continuation намеренно переживает cancel,
/// чтобы проверить защиту от ответов, которые уже нельзя физически остановить.
@MainActor
final class ControlledEngine: TranslationEngine {
    var languages = [TranslationLanguage(id: "en"), TranslationLanguage(id: "ru"), TranslationLanguage(id: "de")]
    var requiresDownload = false
    var readinessFailure: TranslationFailure?
    var requests: [UUID: TranslationRequest] = [:]
    var pending: [UUID: CheckedContinuation<TranslationResult, Error>] = [:]
    var completedCalls = 0

    func supportedLanguages() async throws -> [TranslationLanguage] { languages }

    func readiness(for request: TranslationRequest) async throws -> TranslationReadiness {
        if let readinessFailure { throw readinessFailure }
        let resolved = try request.resolvingSource(request.source ?? TranslationLanguage(id: "en"))
        return requiresDownload ? .needsDownload(resolved) : .installed(resolved)
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        requests[request.id] = request
        defer { completedCalls += 1 }
        return try await withCheckedThrowingContinuation { pending[request.id] = $0 }
    }

    func cancel() {
        // Здесь специально нет resume/cancel: тест доказывает защиту model, а не fake engine.
    }

    func respond(to id: UUID, text: String) throws {
        guard let request = requests[id], let source = request.source,
              let continuation = pending.removeValue(forKey: id) else {
            throw ManualTestError.assertion("Unknown pending request")
        }
        continuation.resume(returning: TranslationResult(
            requestID: id, text: text, source: source, target: request.target
        ))
    }

    func fail(_ id: UUID, with failure: TranslationFailure = .failed) throws {
        guard let continuation = pending.removeValue(forKey: id) else {
            throw ManualTestError.assertion("Unknown pending request")
        }
        continuation.resume(throwing: failure)
    }
}

@main
struct ManualTranslationTests {
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ManualTestError.assertion(message) }
    }

    @MainActor static func waitUntil(_ condition: () -> Bool) async throws {
        let end = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < end else { throw ManualTestError.assertion("Wait timed out") }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor static func settle() async {
        for _ in 0..<12 { await Task.yield() }
    }

    @MainActor static func fixture(timeout: Duration = .seconds(60)) async -> (ManualTranslationModel, ControlledEngine) {
        let engine = ControlledEngine()
        let model = ManualTranslationModel(engine: engine, timeout: timeout, context: .capture)
        await model.loadLanguages()
        return (model, engine)
    }

    @MainActor static func start(_ model: ManualTranslationModel, _ engine: ControlledEngine, text: String) async throws -> UUID {
        model.sourceText = text
        model.submit()
        try await waitUntil { engine.pending.count == 1 }
        guard let id = engine.pending.keys.first else { throw ManualTestError.assertion("Missing request") }
        return id
    }

    @MainActor static func main() async {
        var passed: [String] = []
        func test(_ name: String, _ action: @MainActor () async throws -> Void) async throws {
            try await action()
            passed.append(name)
        }
        do {
            try await test("whitespace-only input rejected") {
                do {
                    _ = try TranslationRequest(text: " \n\t ", source: nil, target: TranslationLanguage(id: "ru"))
                    throw ManualTestError.assertion("Expected emptyText")
                } catch TranslationFailure.emptyText {}
            }
            try await test("multiline input preserved") {
                let text = "  Hello\nworld!  "
                let request = try TranslationRequest(text: text, source: nil, target: TranslationLanguage(id: "ru"))
                try expect(request.text == text, "Input whitespace was changed")
            }
            try await test("application text limit boundary") {
                let text = String(repeating: "a", count: TranslationRequest.characterLimit)
                _ = try TranslationRequest(text: text, source: nil, target: TranslationLanguage(id: "ru"))
                do {
                    _ = try TranslationRequest(text: text + "a", source: nil, target: TranslationLanguage(id: "ru"))
                    throw ManualTestError.assertion("Expected textTooLong")
                } catch TranslationFailure.textTooLong {}
            }
            try await test("same base language rejected") {
                do {
                    _ = try TranslationRequest(text: "Hello", source: TranslationLanguage(id: "en-GB"), target: TranslationLanguage(id: "en"))
                    throw ManualTestError.assertion("Expected sameLanguage")
                } catch TranslationFailure.sameLanguage {}
            }
            try await test("successful result belongs to request snapshot") {
                let (model, engine) = await fixture()
                let id = try await start(model, engine, text: "Hello, world!")
                try engine.respond(to: id, text: "Здравствуйте!")
                try await waitUntil { model.phase == .completed }
                try expect(model.result?.requestID == id && model.result?.text == "Здравствуйте!", "Result mismatch")
            }
            try await test("cancel ignores late success") {
                let (model, engine) = await fixture()
                let id = try await start(model, engine, text: "Old request")
                model.cancel()
                try engine.respond(to: id, text: "OLD")
                try await waitUntil { engine.completedCalls == 1 }
                await settle()
                try expect(model.result == nil && model.phase == .cancelled, "Late success replaced cancellation")
            }
            try await test("new result survives old success") {
                let (model, engine) = await fixture()
                let old = try await start(model, engine, text: "Old request")
                model.sourceText = "New request"
                model.submit()
                try await waitUntil { engine.pending.count == 2 }
                guard let new = engine.pending.keys.first(where: { $0 != old }) else {
                    throw ManualTestError.assertion("Missing new request")
                }
                try engine.respond(to: new, text: "NEW")
                try await waitUntil { model.result?.text == "NEW" }
                try engine.respond(to: old, text: "OLD")
                try await waitUntil { engine.completedCalls == 2 }
                await settle()
                try expect(model.result?.text == "NEW" && model.phase == .completed, "Old success overwrote new output")
            }
            try await test("old failure cannot replace new success") {
                let (model, engine) = await fixture()
                let old = try await start(model, engine, text: "Old request")
                model.sourceText = "New request"
                model.submit()
                try await waitUntil { engine.pending.count == 2 }
                guard let new = engine.pending.keys.first(where: { $0 != old }) else { throw ManualTestError.assertion("Missing new") }
                try engine.respond(to: new, text: "NEW")
                try await waitUntil { model.phase == .completed }
                try engine.fail(old)
                try await waitUntil { engine.completedCalls == 2 }
                await settle()
                try expect(model.failure == nil && model.result?.text == "NEW", "Old error overwrote success")
            }
            try await test("deadline fails and ignores late result") {
                let (model, engine) = await fixture(timeout: .milliseconds(30))
                let id = try await start(model, engine, text: "Slow request")
                try await waitUntil { model.failure == .timedOut }
                try engine.respond(to: id, text: "TOO LATE")
                try await waitUntil { engine.completedCalls == 1 }
                await settle()
                try expect(model.result == nil && model.phase == .failed && model.failure == .timedOut, "Deadline lost")
            }
            try await test("missing models do not invoke translation") {
                let (model, engine) = await fixture()
                engine.requiresDownload = true
                model.sourceText = "Hello"
                model.submit()
                try await waitUntil { model.phase == .needsDownload }
                try expect(engine.requests.isEmpty && model.result == nil, "Uninstalled model was used")
                model.requestLanguagePreparation()
                try expect(model.preparation != nil && model.phase == .preparing, "Missing preparation ticket")
                model.cancel()
                try expect(model.preparation == nil && model.phase == .cancelled, "Preparation not cancelled")
            }
            try await test("runtime missing models offers explicit preparation for resolved auto pair") {
                let (model, engine) = await fixture()
                let id = try await start(model, engine, text: "Hello")
                try engine.fail(id, with: .modelsNotInstalled)
                try await waitUntil { model.phase == .needsDownload || model.phase == .failed }
                try expect(model.phase == .needsDownload && model.failure == nil, "Runtime missing models did not offer preparation")
                try expect(model.preparation == nil && engine.requests.count == 1, "Preparation or retry started without user action")
                model.requestLanguagePreparation()
                try expect(model.preparation?.request.source?.id == "en" && model.preparation?.request.target.id == "ru", "Detected language pair was lost")
                try expect(model.preparation?.request.text == "Hello", "Preparation lost source snapshot")
                model.cancel()
            }
            try await test("runtime missing models retries only after explicit preparation completes") {
                let (model, engine) = await fixture()
                let id = try await start(model, engine, text: "Hello")
                try engine.fail(id, with: .modelsNotInstalled)
                try await waitUntil { model.phase == .needsDownload }
                model.requestLanguagePreparation()
                guard let ticket = model.preparation else { throw ManualTestError.assertion("Missing recovery ticket") }
                model.finishPreparation(id: ticket.id, failure: nil)
                try await waitUntil { engine.pending.count == 1 }
                guard let retry = engine.pending.keys.first else { throw ManualTestError.assertion("Missing recovery request") }
                try expect(retry != id && engine.requests.count == 2, "Recovery reused obsolete request")
                try engine.respond(to: retry, text: "RECOVERED")
                try await waitUntil { model.phase == .completed }
                try expect(model.result?.text == "RECOVERED", "Recovery result missing")
            }
            try await test("editing input invalidates runtime model recovery") {
                let (model, engine) = await fixture()
                let id = try await start(model, engine, text: "Hello")
                try engine.fail(id, with: .modelsNotInstalled)
                try await waitUntil { model.phase == .needsDownload }
                model.sourceText = "Changed"
                model.requestLanguagePreparation()
                try expect(model.phase == .idle && model.preparation == nil, "Obsolete pair prepared after edit")
            }
            try await test("cancel ignores late runtime missing models") {
                let (model, engine) = await fixture()
                let id = try await start(model, engine, text: "Hello")
                model.cancel()
                try engine.fail(id, with: .modelsNotInstalled)
                try await waitUntil { engine.completedCalls == 1 }
                await settle()
                try expect(model.phase == .cancelled && model.preparation == nil, "Late missing-model error reopened preparation")
            }
            try await test("late runtime missing models cannot replace new success") {
                let (model, engine) = await fixture()
                let old = try await start(model, engine, text: "Old")
                model.sourceText = "New"
                model.submit()
                try await waitUntil { engine.pending.count == 2 }
                guard let new = engine.pending.keys.first(where: { $0 != old }) else { throw ManualTestError.assertion("Missing new request") }
                try engine.respond(to: new, text: "NEW")
                try await waitUntil { model.phase == .completed }
                try engine.fail(old, with: .modelsNotInstalled)
                try await waitUntil { engine.completedCalls == 2 }
                await settle()
                try expect(model.phase == .completed && model.result?.text == "NEW", "Late recovery replaced new result")
            }
            try await test("ordinary translation failure does not offer model preparation") {
                let (model, engine) = await fixture()
                let id = try await start(model, engine, text: "Hello")
                try engine.fail(id)
                try await waitUntil { model.phase == .failed }
                model.requestLanguagePreparation()
                try expect(model.failure == .failed && model.preparation == nil, "Unrelated error offered language download")
            }
            try await test("preparation rechecks models before translation") {
                let (model, engine) = await fixture()
                engine.requiresDownload = true
                model.sourceText = "Hello"
                model.submit()
                try await waitUntil { model.phase == .needsDownload }
                model.requestLanguagePreparation()
                guard let id = model.preparation?.id else { throw ManualTestError.assertion("Missing ticket") }
                engine.requiresDownload = false
                model.finishPreparation(id: id, failure: nil)
                try await waitUntil { engine.pending.count == 1 }
                guard let requestID = engine.pending.keys.first else { throw ManualTestError.assertion("Missing retry") }
                try engine.respond(to: requestID, text: "READY")
                try await waitUntil { model.result?.text == "READY" }
            }
            try await test("obsolete preparation callback ignored") {
                let (model, engine) = await fixture()
                engine.requiresDownload = true
                model.sourceText = "Hello"
                model.submit()
                try await waitUntil { model.phase == .needsDownload }
                model.requestLanguagePreparation()
                guard let id = model.preparation?.id else { throw ManualTestError.assertion("Missing ticket") }
                model.sourceText = "Changed"
                model.finishPreparation(id: id, failure: nil)
                try expect(model.phase == .idle && model.preparation == nil && engine.requests.isEmpty, "Stale download started translation")
            }
            try await test("swap keeps prior output as new source") {
                let (model, engine) = await fixture()
                let id = try await start(model, engine, text: "Hello")
                try engine.respond(to: id, text: "Привет")
                try await waitUntil { model.phase == .completed }
                model.swapLanguages()
                try expect(model.sourceIdentifier == "ru" && model.targetIdentifier == "en", "Wrong swapped languages")
                try expect(model.sourceText == "Привет" && model.result == nil, "Swap lost prior output")
            }
            try await test("unsupported pair reports error without fake result") {
                let (model, engine) = await fixture()
                engine.readinessFailure = .unsupportedPair
                model.sourceText = "Hello"
                model.submit()
                try await waitUntil { model.phase == .failed }
                try expect(model.failure == .unsupportedPair && model.result == nil && engine.requests.isEmpty, "Unsupported pair invoked translator")
            }
            try await test("empty system catalogue has explicit unavailable state") {
                let engine = ControlledEngine()
                engine.languages = []
                let model = ManualTranslationModel(engine: engine)
                await model.loadLanguages()
                try expect(model.catalogFailure != nil && !model.canTranslate, "Empty catalogue treated as available")
            }
            let report: [String: Any] = ["status": "passed", "count": passed.count, "tests": passed]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            let report: [String: Any] = ["status": "failed", "passed": passed, "error": String(describing: error)]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            exit(1)
        }
    }
}
