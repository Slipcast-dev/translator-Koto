import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Статус отделяет отсутствие моделей, ошибку и отмену от успешного результата.
struct TranslationStatusView: View {
    let model: ManualTranslationModel

    private var message: String {
        if let failure = model.failure { return failure.errorDescription ?? String(localized: "Translation error.") }
        switch model.phase {
        case .idle: return "\(model.engineName) · \(readiness.text)"
        case .checking: return String(localized: "Checking language resources…")
        case .translating: return String(localized: "Translating…")
        case .needsDownload: return String(localized: "Prepare languages for this pair.")
        case .preparing: return String(localized: "Waiting for system language preparation…")
        case .completed: return String(localized: "Done · \(model.engineName)")
        case .cancelled: return String(localized: "Translation cancelled.")
        case .failed: return String(localized: "Unable to translate.")
        }
    }

    private var readiness: EngineReadiness {
        EngineStatus.shared.readiness(
            of: EnginePreferences.shared.selected, languagesLoaded: !model.languages.isEmpty,
            loadingLanguages: model.isLoadingLanguages, catalogFailure: model.catalogFailure)
    }
    /// Подсказка о неготовом движке показывается только в покое: ошибки и прогресс важнее.
    private var warnsAboutEngine: Bool {
        model.failure == nil && model.phase == .idle && !readiness.isReady
    }

    var body: some View {
        HStack(spacing: 9) {
            if model.isBusy || (model.phase == .idle && readiness.isLoading) { ProgressView().controlSize(.small) }
            else {
                Image(systemName: model.failure != nil ? "exclamationmark.triangle"
                      : warnsAboutEngine ? "exclamationmark.circle" : "globe")
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(model.failure != nil ? Color.red : warnsAboutEngine ? Color.orange : Color.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if model.phase == .needsDownload {
                Button(String(localized: "Prepare languages")) { model.requestLanguagePreparation() }
                    .accessibilityIdentifier("translation.prepareLanguages")
            }
        }
        .accessibilityIdentifier("translation.status")
    }
}
