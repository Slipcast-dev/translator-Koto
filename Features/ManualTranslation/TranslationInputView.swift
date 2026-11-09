import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Исходный текст не сохраняется через AppStorage/SceneStorage: он живёт только в состоянии окна.
struct TranslationInputView: View {
    @Bindable var model: ManualTranslationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Source text")).font(.headline)
                Spacer()
                Text(AppLocalization.characterCounter(model.sourceText.count, limit: TranslationRequest.characterLimit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(model.sourceText.count > TranslationRequest.characterLimit ? Color.red : Color.secondary)
            }
            TextEditor(text: $model.sourceText)
                .font(.body)
                // Меняется направление ввода, но не порядок кнопок и колонок оболочки.
                .environment(\.layoutDirection, AppLocalization.isRightToLeft(language: model.sourceIdentifier, text: model.sourceText) ? .rightToLeft : .leftToRight)
                .scrollContentBackground(.hidden)
                .padding(8)
                .overlay(alignment: .topLeading) {
                    if model.sourceText.isEmpty {
                        Text(String(localized: "Enter text to translate"))
                            .foregroundStyle(.tertiary)
                            .padding(12)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
                .accessibilityLabel(String(localized: "Source text"))
                .accessibilityIdentifier("translation.input")
            HStack {
                Button { model.clear() } label: { Label(String(localized: "Clear"), systemImage: "trash") }
                    .disabled(model.sourceText.isEmpty && model.result == nil)
                    .help(String(localized: "Clear text and translation"))
                    .accessibilityIdentifier("translation.clear")
                Spacer()
                if model.isBusy {
                    Button { model.cancel() } label: { Label(String(localized: "Cancel"), systemImage: "stop.circle") }
                        .keyboardShortcut(.escape, modifiers: [])
                        .help(String(localized: "Cancel translation · Esc"))
                        .accessibilityIdentifier("translation.cancel")
                } else {
                    Button { model.submit() } label: { Label(String(localized: "Translate"), systemImage: "arrow.right.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!model.canTranslate)
                        .help(String(localized: "Translate · ⌘↩"))
                        .accessibilityIdentifier("translation.submit")
                }
            }
            .labelStyle(.titleAndIcon).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
