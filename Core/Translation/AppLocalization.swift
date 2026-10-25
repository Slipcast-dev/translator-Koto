import Foundation
import NaturalLanguage

/// Чистые функции nonisolated доступны в том числе из LocalizedError/Sendable.
/// Язык ресурсов и регион форматирования независимы. Хранимые языковые коды,
/// числа протокола и пользовательский текст через эти функции не преобразуются.
enum AppLocalization {
    nonisolated static var languageIdentifier: String {
        Bundle.main.preferredLocalizations.first == "ru" ? "ru" : "en"
    }

    nonisolated static func number(_ value: Int, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale))
    }

    nonisolated static func bytes(
        _ value: Int64, locale: Locale = .current, exact: Bool = false
    ) -> String {
        // Десятичный размер соответствует bytes из каталога модели. Для ошибки
        // нехватки места показываем и точные байты, чтобы округление не занизило порог.
        value.formatted(.byteCount(
            style: .decimal, allowedUnits: .all,
            spellsOutZero: false, includesActualByteCount: exact
        ).locale(locale))
    }

    nonisolated static func characterCounter(
        _ count: Int, limit: Int, locale: Locale = .current
    ) -> String {
        String(localized: "\(number(count, locale: locale)) / \(number(limit, locale: locale))")
    }

    /// Грамматика зависит от языка интерфейса, а не от региона чисел.
    /// Для этих целых счётчиков правила plural явно привязаны к языку каталога.
    nonisolated static func capturedCharacters(_ count: Int) -> String {
        String(localized: "Captured \(count) characters. The target language comes from the main window.",
               locale: Locale(identifier: languageIdentifier))
    }

    nonisolated static func clearMemoryLabel(_ count: Int) -> String {
        String(localized: "Clear memory (\(count))",
               locale: Locale(identifier: languageIdentifier))
    }

    /// Направление только текстового содержимого, а не всей оболочки.
    /// При auto анализ ограничен первыми 512 символами и не меняет язык запроса
    /// перевода: короткий/неопределённый текст безопасно остаётся LTR.
    nonisolated static func isRightToLeft(language: String?, text: String = "") -> Bool {
        let identifier: String
        if let language, language != "auto" {
            identifier = language
        } else {
            identifier = NLLanguageRecognizer.dominantLanguage(
                for: String(text.prefix(512))
            )?.rawValue ?? "en"
        }
        return Locale.Language(identifier: identifier).characterDirection == .rightToLeft
    }
}
