import SafariServices
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Расширение Safari встроено в приложение; включается и выключается только самим Safari.
/// Koto не может сделать это тихо, поэтому кнопки открывают нужный раздел настроек Safari.
struct SafariSettingsView: View {
    nonisolated static let extensionIdentifier = "dev.slipcast.koto.safari"
    private enum ExtensionState { case checking, enabled, disabled, notFound }
    @Bindable private var bridge = BrowserBridgeServer.shared
    @State private var state = ExtensionState.checking
    @State private var message = ""

    private var stateText: String {
        switch state {
        case .checking: String(localized: "Checking…")
        case .enabled: String(localized: "Enabled in Safari")
        case .disabled: String(localized: "Installed, turned off in Safari")
        case .notFound: String(localized: "Not found")
        }
    }

    var body: some View {
        Section(String(localized: "Safari browser")) {
            LabeledContent(String(localized: "Safari extension"), value: stateText)
            HStack {
                Button(String(localized: "Turn on in Safari")) { openPreferences() }
                    .buttonStyle(.borderedProminent).disabled(state == .enabled)
                Button(String(localized: "Turn off in Safari")) { openPreferences() }.disabled(state != .enabled)
                Button(String(localized: "Refresh status")) { refresh() }
            }
            if state == .notFound {
                Text(String(localized: "Safari does not see the extension yet. Move Koto to Applications, launch it once, then refresh."))
                    .font(.caption).foregroundStyle(.orange)
            }
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
            Text(String(localized: "In Safari open Settings → Extensions and tick Koto. This build is not signed with an Apple Developer ID: first enable Develop → Allow Unsigned Extensions in Safari (the choice resets when Safari quits)."))
                .font(.caption).foregroundStyle(.secondary)
            Text(String(localized: "The Safari extension uses the same bridge as Chrome: the “Enable browser bridge” switch above pauses it without removing anything."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        state = .checking
        // async-версия вместо completionHandler: SDK помечает обработчик как @MainActor, а XPC вызывает его
        // на служебной очереди, и приложение падает на проверке изоляции (подтверждено crash-отчётами).
        Task { @MainActor in
            do {
                let extensionState = try await SFSafariExtensionManager.stateOfSafariExtension(withIdentifier: Self.extensionIdentifier)
                state = extensionState.isEnabled ? .enabled : .disabled
            } catch { state = .notFound }
        }
    }

    private func openPreferences() {
        Task { @MainActor in
            do {
                try await SFSafariApplication.showPreferencesForExtension(withIdentifier: Self.extensionIdentifier)
                message = ""
            } catch {
                message = String(localized: "Unable to open Safari settings. Open Safari → Settings → Extensions manually.")
            }
        }
    }
}
