import Foundation

/// Языковые идентификаторы берутся из системного каталога, а подписи локализуются отдельно.
struct TranslationLanguage: Hashable, Identifiable, Sendable {
    let id: String

    var localeLanguage: Locale.Language { Locale.Language(identifier: id) }
    var displayName: String {
        Locale(identifier: "ru").localizedString(forIdentifier: id) ?? id
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
    case modelsNotInstalled, serviceUnavailable, failed, timedOut, cancelled

    var errorDescription: String? {
        switch self {
        case .engineIssue(let message): message
        case .emptyText: "Введите текст для перевода."
        case .textTooLong: "Текст слишком длинный. Разделите его на части до 20 000 символов."
        case .sameLanguage: "Выберите разные языки источника и перевода."
        case .unableToIdentify: "Не удалось уверенно определить язык. Выберите его вручную."
        case .unsupportedPair: "Выбранный движок не поддерживает эту языковую пару."
        case .modelsNotInstalled: "Языковые ресурсы ещё не установлены."
        case .serviceUnavailable: "Системный перевод сейчас недоступен. Попробуйте обновить список языков."
        case .failed: "Не удалось выполнить перевод. Повторите попытку."
        case .timedOut: "Перевод занял слишком много времени. Попробуйте ещё раз."
        case .cancelled: "Перевод отменён."
        }
    }
}
