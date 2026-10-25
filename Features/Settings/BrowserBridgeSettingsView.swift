import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

struct BrowserBridgeSettingsView: View {
    @Bindable var bridge = BrowserBridgeServer.shared
    @State private var registration = ""
    var body: some View {
        Section(String(localized: "Chromium browser")) {
            Toggle(String(localized: "Enable browser bridge"), isOn: $bridge.enabled)
            Text(bridge.status).font(.caption).foregroundStyle(.secondary)
            Button(String(localized: "Register native host for Chrome")) {
                do { try BrowserHostInstaller.installForChrome(); registration = String(localized: "Native host registered for this copy of Koto.") }
                catch { registration = String(localized: "Unable to register the host. Check the Koto installation and directory permissions.") }
            }
            if !registration.isEmpty { Text(registration).font(.caption) }
            Text(String(localized: "After registration, load the BrowserExtension folder as an unpacked extension at chrome://extensions. Use only the Koto extension with ID \(BridgeOrigin.allowed)."))
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(String(localized: "The bridge accepts only Koto’s own extension, uses a local Unix socket and authenticates every connection."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
