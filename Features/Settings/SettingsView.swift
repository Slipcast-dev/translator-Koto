import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Настройки разложены по пяти вкладкам по смыслу, чтобы не листать один длинный список.
struct SettingsView: View {
    let capture: CaptureCoordinator

    var body: some View {
        TabView {
            Tab(String(localized: "General"), systemImage: "gearshape") {
                Form {
                    UpdateSettingsView()
                    Section(String(localized: "Appearance")) { AppearancePicker() }
                    LoginSettingsView()
                    CaptureSettingsView(coordinator: capture)
                }
                .formStyle(.grouped)
            }
            Tab(String(localized: "Translation"), systemImage: "character.bubble") {
                Form {
                    LocalRuntimeSettingsView()
                    CloudSettingsView()
                }
                .formStyle(.grouped)
            }
            Tab(String(localized: "Privacy"), systemImage: "hand.raised") {
                Form { PrivacySettingsView() }.formStyle(.grouped)
            }
            Tab(String(localized: "Browsers"), systemImage: "safari") {
                Form {
                    BrowserBridgeSettingsView()
                    SafariSettingsView()
                }
                .formStyle(.grouped)
            }
            Tab(String(localized: "Advanced"), systemImage: "slider.horizontal.3") {
                Form {
                    SettingsMigrationView(model: capture.manualModel)
                    DiagnosticsSettingsView()
                    Section(String(localized: "Application")) {
                        LabeledContent(String(localized: "Name"), value: ProductInfo.name)
                        LabeledContent(String(localized: "Developer"), value: ProductInfo.developer)
                        LabeledContent(String(localized: "Version"), value: "\(ProductInfo.version) (\(ProductInfo.build))")
                        if let license = URL(string: "https://github.com/Slipcast-dev/translator-Koto/blob/main/LICENSE") {
                            Link(String(localized: "License"), destination: license)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 620, height: 600)
        .accessibilityIdentifier("koto.settings")
    }
}
