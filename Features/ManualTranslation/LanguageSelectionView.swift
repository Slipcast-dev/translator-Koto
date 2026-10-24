import SwiftUI

/// Оба списка строятся из системного каталога; неподдерживаемые языки не выдаются за доступные.
struct LanguageSelectionView: View {
    @Bindable var model: ManualTranslationModel

    var body: some View {
        HStack(spacing: 14) {
            Picker("С языка", selection: $model.sourceIdentifier) {
                Text("Определить язык").tag("auto")
                ForEach(model.languages) { language in
                    Text(language.displayName).tag(language.id)
                }
            }
            .accessibilityIdentifier("translation.sourceLanguage")
            Button { model.swapLanguages() } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Поменять языки местами")
            .accessibilityLabel("Поменять языки местами")
            .accessibilityIdentifier("translation.swap")
            .disabled(!model.canSwap)
            Picker("На язык", selection: $model.targetIdentifier) {
                if model.languages.isEmpty { Text("Загрузка…").tag(model.targetIdentifier) }
                ForEach(model.languages) { language in
                    Text(language.displayName).tag(language.id)
                }
            }
            .accessibilityIdentifier("translation.targetLanguage")
        }
        .disabled(model.isLoadingLanguages || model.languages.isEmpty)
    }
}
