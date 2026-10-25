import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Переключатели управляют реальной регистрацией, а права запрашиваются только явными кнопками.
struct CaptureSettingsView: View {
    @Bindable var coordinator: CaptureCoordinator
    var body: some View {
        Section(String(localized: "Translate from other apps")) {
            Toggle(String(localized: "Global keyboard shortcuts"), isOn: $coordinator.hotkeysEnabled)
            Text(String(localized: "⌃⌥⌘T — selected text\n⌃⌥⌘R — screen region (OCR)\n⌃⌥⌘L — live translation"))
                .font(.callout).foregroundStyle(.secondary)
            if let issue = coordinator.hotkeyIssue { Text(issue).foregroundStyle(.red) }
            Text(String(localized: "Alternative: choose Services → Translate in Koto in the source app. The system service passes only selected text and does not change the clipboard."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "Selection access")) { coordinator.requestAccessibility() }
                Button(String(localized: "Screen access")) { coordinator.requestScreen() }
                Button(String(localized: "Check")) { coordinator.refreshPermissions() }
            }
            Text(String(localized: "Selection: \(coordinator.accessibilityGranted ? String(localized: "granted") : String(localized: "not granted")) · Screen: \(coordinator.screenGranted ? String(localized: "granted") : String(localized: "not granted"))"))
                .font(.caption)
            Text(String(localized: "These permissions are not required for manual translation. You may need to restart Koto after changing access."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { coordinator.refreshPermissions() }
    }
}
