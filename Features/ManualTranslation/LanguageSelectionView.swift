import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Оба списка строятся из системного каталога; неподдерживаемые языки не выдаются за доступные.
struct LanguageSelectionView: View {
    @Bindable var model: ManualTranslationModel

    var body: some View {
        HStack(spacing: 14) {
            Picker(String(localized: "From"), selection: $model.sourceIdentifier) {
                Text(String(localized: "Detect language")).tag("auto")
                ForEach(model.languages) { language in
                    Text(language.displayName).tag(language.id)
                }
            }
            .accessibilityIdentifier("translation.sourceLanguage")
            Button { model.swapLanguages() } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help(String(localized: "Swap languages"))
            .accessibilityLabel(String(localized: "Swap languages"))
            .accessibilityIdentifier("translation.swap")
            .disabled(!model.canSwap)
            Picker(String(localized: "To"), selection: $model.targetIdentifier) {
                if model.languages.isEmpty { Text(String(localized: "Loading…")).tag(model.targetIdentifier) }
                ForEach(model.languages) { language in
                    Text(language.displayName).tag(language.id)
                }
            }
            .accessibilityIdentifier("translation.targetLanguage")
        }
        .disabled(model.isLoadingLanguages || model.languages.isEmpty)
    }
}
