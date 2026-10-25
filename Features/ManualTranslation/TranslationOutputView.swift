import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Вывод доступен для выделения, но не редактирования; копирование всегда относится к актуальному result.
struct TranslationOutputView: View {
    let result: TranslationResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Translation")).font(.headline)
                Spacer()
                if let result {
                    Text(result.source.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                Text(result?.text ?? String(localized: "Your translation will appear here"))
                    .font(.body)
                    .foregroundStyle(result == nil ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .environment(\.layoutDirection, AppLocalization.isRightToLeft(language: result?.target.id, text: result?.text ?? "") ? .rightToLeft : .leftToRight)
                    .padding(12)
                    .accessibilityIdentifier("translation.output")
            }
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
