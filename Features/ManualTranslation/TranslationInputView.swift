import SwiftUI

/// Исходный текст не сохраняется через AppStorage/SceneStorage: он живёт только в состоянии окна.
struct TranslationInputView: View {
    @Bindable var model: ManualTranslationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Исходный текст").font(.headline)
                Spacer()
                Text("\(model.sourceText.count) / 20 000")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(model.sourceText.count > TranslationRequest.characterLimit ? Color.red : Color.secondary)
            }
            TextEditor(text: $model.sourceText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .overlay(alignment: .topLeading) {
                    if model.sourceText.isEmpty {
                        Text("Введите текст для перевода")
                            .foregroundStyle(.tertiary)
                            .padding(12)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
                .accessibilityLabel("Исходный текст")
                .accessibilityIdentifier("translation.input")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
