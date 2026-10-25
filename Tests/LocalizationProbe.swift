import Foundation

/// Каждый запуск — новый процесс с собственными AppleLanguages/AppleLocale.
/// Поэтому кэш Bundle и форматтеров не смешивает проверяемые языки и регионы.
@main
struct LocalizationProbe {
    @MainActor static func main() throws {
        let service = Bundle.main.localizedString(
            forKey: "Translate in Koto", value: "Translate in Koto", table: "ServicesMenu"
        )
        let counts = [0, 1, 2, 5, 21, 22]
        let settings = try SettingsMigration.parse(Data(
            #"{"schema":1,"appearance":"dark","source":"ar","target":"en"}"#.utf8
        ))
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))
        let record: [String: Any] = [
            "preferred": Bundle.main.preferredLocalizations,
            "available": Bundle.main.localizations,
            "development": Bundle.main.developmentLocalization ?? "",
            "formatting_locale": Locale.current.identifier,
            "about": String(localized: "About Koto"),
            "empty_error": TranslationFailure.emptyText.errorDescription ?? "",
            "same_language": TranslationFailure.sameLanguage.errorDescription ?? "",
            "cloud_denied": TranslationFailure.cloudNotAllowed.errorDescription ?? "",
            "german_name": TranslationLanguage(id: "de").displayName,
            "counter": AppLocalization.characterCounter(42, limit: TranslationRequest.characterLimit),
            "number": AppLocalization.number(1_234_567),
            "bytes": AppLocalization.bytes(2_500_000_000),
            "captured": counts.map { AppLocalization.capturedCharacters($0) },
            "clear_memory": counts.map { AppLocalization.clearMemoryLabel($0) },
            "saved_settings": saved,
            "service": service,
            "missing_key": String(localized: "localization.probe.absent", defaultValue: "Fallback available")
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
