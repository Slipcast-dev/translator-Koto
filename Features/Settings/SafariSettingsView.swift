import SafariServices
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Расширение Safari встроено в приложение; включается и выключается только самим Safari.
/// Koto не может сделать это тихо, поэтому кнопки открывают нужный раздел настроек Safari.
struct SafariSettingsView: View {
    static let extensionIdentifier = "dev.slipcast.koto.safari"
    private enum State { case checking, enabled, disabled, notFound }
    @Bindable private var bridge = BrowserBridgeServer.shared
    @State private var state = State.checking
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
            Text(String(localized: "In Safari open Settings → Extensions and tick Koto. This preview build is not signed with an Apple Developer ID: first enable Develop → Allow Unsigned Extensions in Safari (the choice resets when Safari quits)."))
                .font(.caption).foregroundStyle(.secondary)
            Text(String(localized: "The Safari extension uses the same bridge as Chrome: the “Enable browser bridge” switch above pauses it without removing anything."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        state = .checking
        // Ответ приходит из XPC на служебной очереди: замыкание обязано быть явно @Sendable,
        // иначе оно наследует изоляцию MainActor и приложение падает на проверке очереди.
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Self.extensionIdentifier) {
            @Sendable (extensionState: SFSafariExtensionState?, error: Error?) in
            let enabled = extensionState?.isEnabled
            let failed = error != nil || extensionState == nil
            Task { @MainActor in
                state = failed ? .notFound : (enabled == true ? .enabled : .disabled)
            }
        }
    }

    private func openPreferences() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: Self.extensionIdentifier) { @Sendable (error: Error?) in
            let failed = error != nil
            Task { @MainActor in
                message = failed ? String(localized: "Unable to open Safari settings. Open Safari → Settings → Extensions manually.") : ""
            }
        }
    }
}
