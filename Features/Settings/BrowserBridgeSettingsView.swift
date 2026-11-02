import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

struct BrowserBridgeSettingsView: View {
    @Bindable var bridge = BrowserBridgeServer.shared
    @State private var installed = BrowserHostInstaller.isChromeInstalled
    @State private var message = ""
    var body: some View {
        Section(String(localized: "Chromium browser")) {
            // Тумблер только включает или выключает мост; регистрация и файлы расширения не трогаются.
            Toggle(String(localized: "Enable browser bridge"), isOn: $bridge.enabled)
            Text(bridge.status).font(.caption).foregroundStyle(.secondary)
            LabeledContent(String(localized: "Chrome extension"),
                           value: installed ? String(localized: "Installed") : String(localized: "Not installed"))
            HStack {
                Button(String(localized: "Install extension for Chrome")) { install() }
                    .buttonStyle(.borderedProminent)
                Button(String(localized: "Remove extension")) { remove() }.disabled(!installed)
            }
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
            Text(String(localized: "Chrome asks you to confirm unpacked extensions: after installing, turn on Developer mode at chrome://extensions, click “Load unpacked” and choose the folder that opens. The extension ID must be \(BridgeOrigin.allowed)."))
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(String(localized: "The switch above only turns the bridge on or off; it never removes the extension. The bridge accepts only Koto’s own extension, uses a local Unix socket and authenticates every connection."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { installed = BrowserHostInstaller.isChromeInstalled }
    }

    private func install() {
        do {
            try BrowserHostInstaller.installChrome()
            installed = BrowserHostInstaller.isChromeInstalled
            message = String(localized: "Extension files and the native host are ready. Finish loading the extension in Chrome.")
            NSWorkspace.shared.activateFileViewerSelecting([BrowserHostInstaller.extensionDirectory])
            if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
               let page = URL(string: "chrome://extensions") {
                NSWorkspace.shared.open([page], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
            } else {
                message += " " + String(localized: "Google Chrome was not found: open chrome://extensions in your Chromium browser.")
            }
        } catch {
            message = String(localized: "Unable to install the extension. Check the Koto installation and directory permissions.")
        }
    }

    private func remove() {
        do {
            try BrowserHostInstaller.removeChrome()
            installed = BrowserHostInstaller.isChromeInstalled
            message = String(localized: "Native host and extension files removed. Also remove the Koto extension at chrome://extensions.")
        } catch {
            message = String(localized: "Unable to remove the extension files. Check access to the Koto directory.")
        }
    }
}
