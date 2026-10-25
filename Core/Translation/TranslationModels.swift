import Foundation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Языковые идентификаторы берутся из системного каталога, а подписи локализуются отдельно.
struct TranslationLanguage: Hashable, Identifiable, Sendable {
    let id: String

    var localeLanguage: Locale.Language { Locale.Language(identifier: id) }
    var displayName: String {
        Locale(identifier: AppLocalization.languageIdentifier)
            .localizedString(forIdentifier: id) ?? id
    }
}

/// Неизменяемый снимок ввода: последующее редактирование UI не меняет выполняемый запрос.
struct TranslationRequest: Sendable {
    nonisolated static let characterLimit = 20_000

    let id: UUID
    let context: TranslationContext
    let text: String
    let source: TranslationLanguage?
    let target: TranslationLanguage

    init(
        id: UUID = UUID(), text: String,
        source: TranslationLanguage?, target: TranslationLanguage, context: TranslationContext = .manual
    ) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationFailure.emptyText
        }
        guard text.count <= Self.characterLimit else { throw TranslationFailure.textTooLong }
        if let source,
           source.localeLanguage.languageCode == target.localeLanguage.languageCode {
            throw TranslationFailure.sameLanguage
        }
        self.id = id
        self.context = context
        // Проверяем пробельный ввод, но сохраняем исходные переносы и пробелы для самого перевода.
        self.text = text
        self.source = source
        self.target = target
    }

    func resolvingSource(_ language: TranslationLanguage) throws -> Self {
        try Self(id: id, text: text, source: language, target: target, context: context)
    }
}

struct TranslationResult: Sendable {
    let requestID: UUID
    let text: String
    let source: TranslationLanguage
    let target: TranslationLanguage
    let engineLabel: String?
    init(requestID: UUID, text: String, source: TranslationLanguage, target: TranslationLanguage, engineLabel: String? = nil) {
        self.requestID = requestID; self.text = text; self.source = source; self.target = target; self.engineLabel = engineLabel
    }
}

/// Готовность содержит разрешённый источник, чтобы загрузка и перевод использовали одну пару.
enum TranslationReadiness: Sendable {
    case installed(TranslationRequest)
    case needsDownload(TranslationRequest)
}

struct LanguagePreparationTicket: Identifiable, Sendable {
    let id = UUID()
    let request: TranslationRequest
}

enum TranslationFailure: Error, LocalizedError, Equatable, Sendable {
    case engineIssue(String)
    case emptyText, textTooLong, sameLanguage, unableToIdentify, unsupportedPair
    case modelsNotInstalled, serviceUnavailable, failed, timedOut, cancelled, cloudNotAllowed

    var errorDescription: String? {
        switch self {
        case .engineIssue(let message): message
        // Машинный код запрета облака не зависит от языка текста ошибки.
        case .cloudNotAllowed:
            String(localized: "Cloud sending is disabled for this source. Enable it separately in privacy settings.")
        case .emptyText:
            // Foundation локализует ошибку и вне SwiftUI; английский ключ даёт резервный текст.
            String(localized: "Enter text to translate.",
                   comment: "Ошибка пустого или пробельного ввода перед переводом.")
        case .textTooLong: String(localized: "The text is too long. Split it into sections of up to \(AppLocalization.number(TranslationRequest.characterLimit)) characters.")
        case .sameLanguage: String(localized: "Choose different source and target languages.")
        case .unableToIdentify: String(localized: "Unable to identify the language reliably. Select it manually.")
        case .unsupportedPair: String(localized: "The selected engine does not support this language pair.")
        case .modelsNotInstalled: String(localized: "Language resources are not installed yet.")
        case .serviceUnavailable: String(localized: "System translation is currently unavailable. Try refreshing the language list.")
        case .failed: String(localized: "Unable to translate. Try again.")
        case .timedOut: String(localized: "Translation took too long. Try again.")
        case .cancelled: String(localized: "Translation cancelled.")
        }
    }
}
