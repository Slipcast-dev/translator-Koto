import SwiftUI

/// Вывод доступен для выделения, но не редактирования; копирование всегда относится к актуальному result.
struct TranslationOutputView: View {
    let result: TranslationResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Перевод").font(.headline)
                Spacer()
                if let result {
                    Text(result.source.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                Text(result?.text ?? "Здесь появится перевод")
                    .font(.body)
                    .foregroundStyle(result == nil ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
                    .accessibilityIdentifier("translation.output")
            }
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
