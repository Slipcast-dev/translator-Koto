import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

extension UpdateModel {
    /// Завершение приложения нужно только для перезапуска после замены bundle.
    static let shared = UpdateModel(terminate: { NSApp.terminate(nil) })
}

/// Раздел настроек: версия, описание, автоматическая проверка и ручное управление обновлением.
/// Сообщения об обновлении показывает главное окно (UpdatePrompts), чтобы они не зависели от окна настроек.
struct UpdateSettingsView: View {
    @Bindable private var model = UpdateModel.shared
    @AppStorage(UpdateModel.autoCheckKey) private var autoCheck = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section(String(localized: "Update")) {
            LabeledContent(String(localized: "Version"), value: "\(ProductInfo.version) (\(ProductInfo.build))")
            Text(String(localized: "Koto is a native macOS translator: text, selections and screen regions, local engines and a Chrome extension."))
                .font(.callout).foregroundStyle(.secondary)
            Toggle(String(localized: "Check for updates when Koto starts"), isOn: $autoCheck)
            HStack {
                Button(String(localized: "Check for updates")) { model.check(); reveal() }
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("update.check")
                if model.isBusy {
                    ProgressView().controlSize(.small)
                    Button(String(localized: "Cancel")) { model.cancel() }
                }
                Spacer()
            }
            if model.phase == .downloading { ProgressView(value: model.progress) }
            Text(model.statusText).font(.caption).foregroundStyle(model.isFailed ? Color.red : Color.secondary)
                .textSelection(.enabled)
            if model.isFailed, let release = model.failedRelease {
                Link(String(localized: "Open the release page"), destination: release.page).font(.caption)
            }
            switch model.phase {
            case .available:
                Button(String(localized: "Show update…")) { model.showPrompt(); reveal() }
            case .readyToRestart:
                HStack {
                    Button(String(localized: "Restart now")) { model.restartNow() }.buttonStyle(.borderedProminent)
                    Text(String(localized: "Or later: the update is applied when you quit Koto.")).font(.caption).foregroundStyle(.secondary)
                }
            default: EmptyView()
            }
        }
    }

    /// Сообщение об обновлении живёт в главном окне: открываем его, если оно было закрыто.
    private func reveal() {
        openWindow(id: WindowID.main)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension UpdateModel {
    var isFailed: Bool { if case .failed = phase { true } else { false } }
}
