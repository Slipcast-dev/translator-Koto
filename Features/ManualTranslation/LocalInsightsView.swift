import SwiftUI

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
            Text("Смысл и выражения · Qwen").font(.title2)
            Text("Объяснения и варианты могут содержать ошибки. Текст обрабатывается на этом Mac.").font(.caption)
            HStack {
                Button("Объяснить") { run(alternatives: false) }
                Button("Варианты перевода") { run(alternatives: true) }
                if busy { ProgressView(); Button("Отмена") { cancel() } }
                Spacer(); Button("Закрыть") { dismiss() }
            }
            ScrollView { Text(output).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(24).frame(width: 640, height: 420).onDisappear { cancel() }
    }
    private func cancel() { generation = UUID(); operation?.cancel(); operation = nil; busy = false }
    private func run(alternatives: Bool) {
        cancel()
        guard !text.isEmpty, text.count <= 500 else { output = "Для пояснения выберите фразу до 500 символов."; return }
        let id = UUID(); generation = id; busy = true; output = ""
        operation = Task {
            defer { if generation == id { busy = false; operation = nil } }
            do {
                let result = try await LocalInsightsService(runtime:.shared).explain(text:text,target:target,alternatives:alternatives)
                try Task.checkCancellation()
                guard generation == id else { return }
                output = result.rendered
            } catch {
                guard generation == id, !Task.isCancelled else { return }
                output = (error as? TranslationFailure)?.errorDescription ?? "Локальное пояснение не завершено. Проверьте ресурсы Qwen и повторите запрос."
            }
        }
    }
}
