import Foundation
import Observation

enum ManualTranslationPhase: Equatable {
    case idle, checking, translating, needsDownload, preparing, completed, cancelled, failed
}

/// UI state machine не зависит от Apple/SwiftUI. UUID связывает результат с точным снимком ввода.
@MainActor @Observable
final class ManualTranslationModel {
    var sourceText = "" { didSet { if sourceText != oldValue { inputChanged() } } }
    var sourceIdentifier = "auto" { didSet { if sourceIdentifier != oldValue { inputChanged(); persistLanguagePreferences() } } }
    var targetIdentifier = "ru" { didSet { if targetIdentifier != oldValue { inputChanged(); persistLanguagePreferences() } } }

    private(set) var languages: [TranslationLanguage] = []
    private(set) var isLoadingLanguages = false
    private(set) var catalogFailure: String?
    private(set) var phase: ManualTranslationPhase = .idle
    private(set) var result: TranslationResult?
    private(set) var failure: TranslationFailure?
    private(set) var preparation: LanguagePreparationTicket?

    @ObservationIgnored private let engine: any TranslationEngine
    @ObservationIgnored private let context: TranslationContext
    @ObservationIgnored private let timeout: Duration?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var activeRequestID: UUID?
    @ObservationIgnored private var languageGeneration = UUID()
    @ObservationIgnored private var downloadableRequest: TranslationRequest?

    init(engine: any TranslationEngine, timeout: Duration? = nil, context: TranslationContext = .manual) {
        self.context = context
        self.engine = engine
        self.timeout = timeout
        if context == .manual {
            sourceIdentifier = UserDefaults.standard.string(forKey: "translation.source") ?? "auto"
            targetIdentifier = UserDefaults.standard.string(forKey: "translation.target") ?? "ru"
        }
    }

    var engineName: String { result?.engineLabel ?? engine.displayName }

    var isBusy: Bool { phase == .checking || phase == .translating || phase == .preparing }
    var canTranslate: Bool {
        !isBusy && !isLoadingLanguages && !languages.isEmpty
            && !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && sourceText.count <= TranslationRequest.characterLimit
    }
    var canSwap: Bool { !isBusy && (sourceIdentifier != "auto" || result != nil) }

    func loadLanguages() async {
        // Повторный вызов означает новый снимок выбранного движка. Старый ответ
        // может физически завершиться позже, но уже не имеет права менять UI.
        let generation = UUID()
        languageGeneration = generation
        languages = []
        isLoadingLanguages = true
        catalogFailure = nil
        defer { if languageGeneration == generation { isLoadingLanguages = false } }
        do {
            let loaded = try await engine.supportedLanguages()
            guard languageGeneration == generation else { return }
            try Task.checkCancellation()
            guard !loaded.isEmpty else { throw TranslationFailure.serviceUnavailable }
            languages = loaded
            if !loaded.contains(where: { $0.id == targetIdentifier }), let first = loaded.first {
                targetIdentifier = loaded.first(where: { $0.id == "ru" })?.id ?? first.id
            }
            if sourceIdentifier != "auto" && !loaded.contains(where: { $0.id == sourceIdentifier }) {
                sourceIdentifier = "auto"
            }
        } catch is CancellationError {
            return
        } catch {
            guard languageGeneration == generation else { return }
            catalogFailure = TranslationFailure.serviceUnavailable.errorDescription
        }
    }

    func submit() {
        stopCurrentOperation()
        result = nil
        failure = nil
        downloadableRequest = nil
        do {
            guard let target = languages.first(where: { $0.id == targetIdentifier }) else {
                throw TranslationFailure.serviceUnavailable
            }
            let source: TranslationLanguage?
            if sourceIdentifier == "auto" {
                source = nil
            } else {
                guard let selected = languages.first(where: { $0.id == sourceIdentifier }) else {
                    throw TranslationFailure.unsupportedPair
                }
                source = selected
            }
            let request = try TranslationRequest(text: sourceText, source: source, target: target, context: context)
            activeRequestID = request.id
            phase = .checking
            startDeadline(for: request.id)
            operation = Task { [weak self] in
                guard let self else { return }
                // Автоопределённый источник должен пережить отказ самой session:
                // подготовке нужна именно проверенная пара, а не повторная догадка UI.
                var preparationRequest: TranslationRequest?
                do {
                    let readiness = try await engine.readiness(for: request)
                    guard activeRequestID == request.id, !Task.isCancelled else { return }
                    switch readiness {
                    case .needsDownload(let resolved):
                        downloadableRequest = resolved
                        phase = .needsDownload
                        finishOperation()
                    case .installed(let resolved):
                        preparationRequest = resolved
                        phase = .translating
                        let translated = try await engine.translate(resolved)
                        // Engine может завершиться после cancel; одного Task.cancel недостаточно.
                        guard activeRequestID == request.id, !Task.isCancelled,
                              translated.requestID == request.id else { return }
                        result = translated
                        phase = .completed
                        finishOperation()
                    }
                } catch {
                    guard activeRequestID == request.id, !Task.isCancelled else { return }
                    let issue = (error as? TranslationFailure) ?? .failed
                    if issue == .modelsNotInstalled, let resolved = preparationRequest,
                       resolved.source != nil {
                        // Между availability и translate ресурсы могут стать недоступны.
                        // Только предлагаем прежний явный сценарий подготовки: sheet,
                        // загрузка и повтор запроса не запускаются автоматически.
                        downloadableRequest = resolved
                        phase = .needsDownload
                    } else {
                        failure = issue
                        phase = issue == .cancelled ? .cancelled : .failed
                    }
                    finishOperation()
                }
            }
        } catch {
            failure = (error as? TranslationFailure) ?? .failed
            phase = .failed
        }
    }

    func requestLanguagePreparation() {
        guard phase == .needsDownload, let request = downloadableRequest else { return }
        stopCurrentOperation()
        let ticket = LanguagePreparationTicket(request: request)
        preparation = ticket
        activeRequestID = ticket.id
        phase = .preparing
    }

    func finishPreparation(id: UUID, failure issue: TranslationFailure?) {
        guard preparation?.id == id, activeRequestID == id else { return }
        preparation = nil
        activeRequestID = nil
        if let issue {
            failure = issue
            phase = issue == .cancelled ? .cancelled : .failed
        } else {
            // После подготовки заново проверяем ресурсы и переводим independent installed session.
            submit()
        }
    }

    func dismissPreparation() {
        guard preparation != nil else { return }
        cancel()
    }

    func cancel() {
        stopCurrentOperation()
        failure = nil
        phase = .cancelled
    }

    func clear() {
        sourceText = ""
        inputChanged()
    }

    func swapLanguages() {
        guard canSwap else { return }
        let previousResult = result
        let oldSource = sourceIdentifier == "auto" ? previousResult?.source.id : sourceIdentifier
        guard let oldSource, languages.contains(where: { $0.id == oldSource }) else { return }
        let oldTarget = targetIdentifier
        sourceIdentifier = oldTarget
        targetIdentifier = oldSource
        if let previousResult { sourceText = previousResult.text }
    }

    private func persistLanguagePreferences() {
        guard context == .manual else { return }
        UserDefaults.standard.set(sourceIdentifier, forKey: "translation.source")
        UserDefaults.standard.set(targetIdentifier, forKey: "translation.target")
    }

    private func inputChanged() {
        stopCurrentOperation()
        result = nil
        failure = nil
        downloadableRequest = nil
        phase = .idle
    }

    private func stopCurrentOperation() {
        // Сначала отзываем ID: запоздалый callback уже не сможет опубликовать состояние.
        activeRequestID = nil
        operation?.cancel()
        operation = nil
        deadline?.cancel()
        deadline = nil
        preparation = nil
        engine.cancel()
    }

    private func finishOperation() {
        deadline?.cancel()
        deadline = nil
        operation = nil
        activeRequestID = nil
    }

    private func startDeadline(for id: UUID) {
        let limit = timeout ?? engine.requestTimeout
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: limit) } catch { return }
            guard let self, activeRequestID == id else { return }
            stopCurrentOperation()
            failure = .timedOut
            phase = .failed
        }
    }
}
