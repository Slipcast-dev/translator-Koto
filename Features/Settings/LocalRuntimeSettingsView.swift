import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Поставка содержит только runtime и каталог. Загрузка весов — одно явное действие пользователя.
struct LocalRuntimeSettingsView: View {
    @Bindable private var runtime = LocalRuntimeSupervisor.shared
    @Bindable private var models = ModelInstallationManager.shared
    @State private var issue: String?
    var body: some View {
        Section(String(localized: "Local translation")) {
            Text(models.displayName).font(.callout)
            Text(String(localized: "Install this model for local translation: \(models.sizeDescription), Apache 2.0. A Mac with 8 GiB of memory is required. The model is not included in the app or installer."))
                .font(.caption).foregroundStyle(.secondary)
            Text(models.status).textSelection(.enabled)
            if models.isBusy {
                if models.isVerifying { ProgressView(String(localized: "Verifying file…")) }
                else {
                    ProgressView(value:models.fraction)
                    Text(models.progressDescription).font(.caption).monospacedDigit()
                }
                Button(String(localized: "Cancel installation")) { models.cancel() }
            } else {
                HStack {
                    Button(models.isInstalled ? String(localized: "Reinstall model") : String(localized: "Install model")) {
                        runtime.stop(); issue = nil; models.install()
                    }.buttonStyle(.borderedProminent)
                        .disabled(models.specification == nil)
                        .accessibilityIdentifier("model.install")
                    Button(String(localized: "Remove model")) { runtime.stop(); models.remove() }
                        .disabled(!models.isInstalled).accessibilityIdentifier("model.remove")
                }
                HStack {
                    Button(String(localized: "Start")) {
                        Task {
                            do { _ = try await runtime.start(); issue = nil }
                            catch { issue = (error as? LocalRuntimeFailure)?.errorDescription ?? String(localized: "Local resources are unavailable.") }
                        }
                    }.disabled(!models.isInstalled || runtime.isRunning)
                    Button(String(localized: "Stop")) { runtime.stop() }.disabled(!runtime.isRunning)
                    Button(String(localized: "License")) {
                        if let file = Bundle.main.url(forResource:"MODEL-LICENSE",withExtension:"txt",subdirectory:"LocalModels") {
                            NSWorkspace.shared.open(file)
                        }
                    }
                }
            }
            Text(String(localized: "After installation, model weights are stored only in your Koto user directory. Apple Translation remains available after removing the model. There is no automatic switch to the cloud."))
                .font(.caption).foregroundStyle(.secondary)
            Text(runtime.status).font(.caption).foregroundStyle(.secondary)
            if let issue { Text(issue).foregroundStyle(.red).font(.caption) }
        }
        .task { models.refresh() }
    }
}
