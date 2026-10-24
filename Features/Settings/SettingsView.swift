import SwiftUI

/// Настройки содержат только реализованное поведение: тема и сведения о текущем приложении.
struct SettingsView: View {
    let capture: CaptureCoordinator
    var body: some View {
        Form {
            Section("Оформление") {
                AppearancePicker()
                Text("Системная тема следует настройкам macOS.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            CaptureSettingsView(coordinator: capture)
            LocalRuntimeSettingsView()
            BrowserBridgeSettingsView()
            ProductSettingsView()
            SettingsMigrationView(model: capture.manualModel)
            Section("Приложение") {
                LabeledContent("Название", value: ProductInfo.name)
                LabeledContent("Разработчик", value: ProductInfo.developer)
                LabeledContent("Версия", value: "\(ProductInfo.version) (\(ProductInfo.build))")
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 740)
        .accessibilityIdentifier("koto.settings")
    }
}
