import AppKit
import SwiftUI

/// Поставка содержит только runtime и каталог. Загрузка весов — одно явное действие пользователя.
struct LocalRuntimeSettingsView: View {
    @Bindable private var runtime = LocalRuntimeSupervisor.shared
    @Bindable private var models = ModelInstallationManager.shared
    @State private var issue: String?
    var body: some View {
        Section("Локальный перевод") {
            Text(models.displayName).font(.callout)
            Text("Для локального перевода установите эту модель: \(models.sizeDescription), Apache 2.0. Нужен Mac с 8 ГБ памяти. Модель не входит в приложение и установщик.")
                .font(.caption).foregroundStyle(.secondary)
            Text(models.status).textSelection(.enabled)
            if models.isBusy {
                if models.isVerifying { ProgressView("Проверяем файл…") }
                else {
                    ProgressView(value:models.fraction)
                    Text(models.progressDescription).font(.caption).monospacedDigit()
                }
                Button("Отменить установку") { models.cancel() }
            } else {
                HStack {
                    Button(models.isInstalled ? "Переустановить модель" : "Установить модель") {
                        runtime.stop(); issue = nil; models.install()
                    }.buttonStyle(.borderedProminent)
                        .disabled(models.specification == nil)
                        .accessibilityIdentifier("model.install")
                    Button("Удалить модель") { runtime.stop(); models.remove() }
                        .disabled(!models.isInstalled).accessibilityIdentifier("model.remove")
                }
                HStack {
                    Button("Запустить") {
                        Task {
                            do { _ = try await runtime.start(); issue = nil }
                            catch { issue = (error as? LocalRuntimeFailure)?.errorDescription ?? "Локальные ресурсы недоступны." }
                        }
                    }.disabled(!models.isInstalled || runtime.isRunning)
                    Button("Остановить") { runtime.stop() }.disabled(!runtime.isRunning)
                    Button("Лицензия") {
                        if let file = Bundle.main.url(forResource:"MODEL-LICENSE",withExtension:"txt",subdirectory:"LocalModels") {
                            NSWorkspace.shared.open(file)
                        }
                    }
                }
            }
            Text("После установки веса хранятся только в пользовательском каталоге Koto. При удалении модели ручной Apple Translation остаётся доступным. Скрытого переключения на облако нет.")
                .font(.caption).foregroundStyle(.secondary)
            Text(runtime.status).font(.caption).foregroundStyle(.secondary)
            if let issue { Text(issue).foregroundStyle(.red).font(.caption) }
        }
        .task { models.refresh() }
    }
}
