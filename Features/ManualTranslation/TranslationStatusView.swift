import SwiftUI

/// Статус отделяет отсутствие моделей, ошибку и отмену от успешного результата.
struct TranslationStatusView: View {
    let model: ManualTranslationModel

    private var message: String {
        if let failure = model.failure { return failure.errorDescription ?? "Ошибка перевода." }
        switch model.phase {
        case .idle: return "\(model.engineName) · На устройстве"
        case .checking: return "Проверяем языковые ресурсы…"
        case .translating: return "Переводим на Mac…"
        case .needsDownload: return "Для этой пары нужно подготовить языки."
        case .preparing: return "Ожидаем системную подготовку языков…"
        case .completed: return "Готово · \(model.engineName)"
        case .cancelled: return "Перевод отменён."
        case .failed: return "Не удалось выполнить перевод."
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            if model.isBusy { ProgressView().controlSize(.small) }
            else {
                Image(systemName: model.failure == nil ? "globe" : "exclamationmark.triangle")
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(model.failure == nil ? Color.secondary : Color.red)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if model.phase == .needsDownload {
                Button("Подготовить языки") { model.requestLanguagePreparation() }
                    .accessibilityIdentifier("translation.prepareLanguages")
            }
        }
        .accessibilityIdentifier("translation.status")
    }
}
