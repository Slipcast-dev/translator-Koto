import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// @AppStorage сохраняет выбор в собственном preferences domain приложения и сообщает другим сценам.
struct AppearancePicker: View {
    @AppStorage(AppAppearance.preferenceKey) private var rawSelection = AppAppearance.system.rawValue

    private var selection: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance.resolve(rawSelection) },
            set: { rawSelection = $0.rawValue }
        )
    }

    var body: some View {
        Picker(String(localized: "Theme"), selection: selection) {
            ForEach(AppAppearance.allCases) { appearance in
                Text(appearance.title).tag(appearance)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("appearance.picker")
    }
}
