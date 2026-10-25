import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Настройки содержат только реализованное поведение: тема и сведения о текущем приложении.
struct SettingsView: View {
    let capture: CaptureCoordinator
    var body: some View {
        Form {
            Section(String(localized: "Appearance")) {
                AppearancePicker()
                Text(String(localized: "The system theme follows macOS settings."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            CaptureSettingsView(coordinator: capture)
            LocalRuntimeSettingsView()
            BrowserBridgeSettingsView()
            ProductSettingsView()
            SettingsMigrationView(model: capture.manualModel)
            Section(String(localized: "Application")) {
                LabeledContent(String(localized: "Name"), value: ProductInfo.name)
                LabeledContent(String(localized: "Developer"), value: ProductInfo.developer)
                LabeledContent(String(localized: "Version"), value: "\(ProductInfo.version) (\(ProductInfo.build))")
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 740)
        .accessibilityIdentifier("koto.settings")
    }
}
