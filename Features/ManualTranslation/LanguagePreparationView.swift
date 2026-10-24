import SwiftUI
// Совместимость ограничена legacy framework; session остаётся внутри системной translationTask.
@preconcurrency import Translation

/// Session из translationTask используется только внутри closure: после dismiss её нельзя переиспользовать.
/// В sheet нет текста запроса; системная подготовка получает только выбранную пару языков.
struct LanguagePreparationView: View {
    let ticket: LanguagePreparationTicket
    let completion: @MainActor (UUID, TranslationFailure?) -> Void
    @State private var configuration: TranslationSession.Configuration?

    init(
        ticket: LanguagePreparationTicket,
        completion: @escaping @MainActor (UUID, TranslationFailure?) -> Void
    ) {
        self.ticket = ticket
        self.completion = completion
        _configuration = State(initialValue: AppleTranslationPolicy.configuration(for: ticket.request))
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Подготовка языков")
                .font(.title2.bold())
            Text("\(ticket.request.source?.displayName ?? "") → \(ticket.request.target.displayName)")
                .font(.headline)
            Text("Apple предложит загрузить языковые ресурсы. Для загрузки нужен интернет; после установки перевод выполняется на Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView()
                .controlSize(.small)
            Button("Отмена") { completion(ticket.id, .cancelled) }
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 440)
        .translationTask(configuration) { session in
            do {
                try Task.checkCancellation()
                try await session.prepareTranslation()
                try Task.checkCancellation()
                completion(ticket.id, nil)
            } catch {
                guard !Task.isCancelled else { return }
                completion(ticket.id, AppleTranslationEngine.failure(for: error))
            }
        }
    }
}
