import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Вывод доступен для выделения, но не редактирования; копирование всегда относится к актуальному result.
struct TranslationOutputView: View {
    let result: TranslationResult?
    /// Готовые части незавершённого перевода. Показываются приглушённо; кнопки копирования их не берут.
    var partial: TranslationProgress? = nil
    var targetIdentifier: String? = nil

    private var partialText: String? {
        guard result == nil, let text = partial?.partialText, !text.isEmpty else { return nil }
        return text
    }
    private var shownText: String { result?.text ?? partialText ?? String(localized: "Your translation will appear here") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Translation")).font(.headline)
                if partialText != nil {
                    Text(String(localized: "incomplete")).font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                if let result {
                    Text(result.source.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                Text(shownText)
                    .font(.body)
                    .foregroundStyle(result != nil ? AnyShapeStyle(.primary)
                                     : partialText != nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .environment(\.layoutDirection, AppLocalization.isRightToLeft(language: result?.target.id ?? targetIdentifier, text: result?.text ?? partialText ?? "") ? .rightToLeft : .leftToRight)
                    .padding(12)
                    .accessibilityIdentifier("translation.output")
            }
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
