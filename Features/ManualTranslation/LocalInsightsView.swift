import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Отдельное локальное действие: объяснение не заменяет основной перевод и не уходит в cloud.
struct LocalInsightsView: View {
    let text: String
    let target: String
    @Environment(\.dismiss) private var dismiss
    @State private var output = ""
    @State private var busy = false
    @State private var operation: Task<Void, Never>?
    @State private var generation = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Meaning and expressions · Qwen")).font(.title2)
            Text(String(localized: "Explanations and alternatives may contain errors. Text is processed on this Mac.")).font(.caption)
            HStack {
                Button(String(localized: "Explain")) { run(alternatives: false) }
                Button(String(localized: "Translation alternatives")) { run(alternatives: true) }
                if busy { ProgressView(); Button(String(localized: "Cancel")) { cancel() } }
                Spacer(); Button(String(localized: "Close")) { dismiss() }
            }
            ScrollView {
                Text(output).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Направление применяется и к выравниванию рамки, не только к глифам.
                    .environment(\.layoutDirection, AppLocalization.isRightToLeft(language: nil, text: output) ? .rightToLeft : .leftToRight)
            }
        }.padding(24).frame(width: 640, height: 420).onDisappear { cancel() }
    }
    private func cancel() { generation = UUID(); operation?.cancel(); operation = nil; busy = false }
    private func run(alternatives: Bool) {
        cancel()
        guard !text.isEmpty, text.count <= 500 else { output = String(localized: "Choose a phrase of up to 500 characters for an explanation."); return }
        let id = UUID(); generation = id; busy = true; output = ""
        // Снимок языка относится к этому запросу, как и target; поздний ответ его не меняет.
        let explanationLanguage = AppLocalization.languageIdentifier
        operation = Task {
            defer { if generation == id { busy = false; operation = nil } }
            do {
                let result = try await LocalInsightsService(runtime:.shared).explain(text:text,target:target,alternatives:alternatives,
                        explanationLanguage: explanationLanguage)
                try Task.checkCancellation()
                guard generation == id else { return }
                output = result.rendered
            } catch {
                guard generation == id, !Task.isCancelled else { return }
                output = (error as? TranslationFailure)?.errorDescription ?? String(localized: "The local explanation did not finish. Check the Qwen resources and try again.")
            }
        }
    }
}
