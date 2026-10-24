import AppKit
import SwiftUI

struct BrowserBridgeSettingsView: View {
    @Bindable var bridge = BrowserBridgeServer.shared
    @State private var registration = ""
    var body: some View {
        Section("Браузер Chromium") {
            Toggle("Разрешить браузерный мост", isOn: $bridge.enabled)
            Text(bridge.status).font(.caption).foregroundStyle(.secondary)
            Button("Зарегистрировать native host для Chrome") {
                do { try BrowserHostInstaller.installForChrome(); registration = "Native host зарегистрирован для текущей копии Koto." }
                catch { registration = "Не удалось зарегистрировать host. Проверьте установку Koto и права каталога." }
            }
            if !registration.isEmpty { Text(registration).font(.caption) }
            Text("После регистрации загрузите папку BrowserExtension как распакованное расширение через chrome://extensions. Используйте только расширение Koto с ID \(BridgeOrigin.allowed).")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Мост принимает только собственное расширение, работает через локальный Unix socket и требует аутентификацию для каждого подключения.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
