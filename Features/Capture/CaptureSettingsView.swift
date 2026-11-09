import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Горячие клавиши и доступы macOS в одном месте. Права запрашиваются только кнопками «Разрешить…».
struct CaptureSettingsView: View {
    @Bindable var coordinator: CaptureCoordinator

    var body: some View {
        Section(String(localized: "Translate from other apps")) {
            Toggle(String(localized: "Global keyboard shortcuts"), isOn: $coordinator.hotkeysEnabled)
            Text(String(localized: "⌃⌥⌘T — selected text\n⌃⌥⌘R — screen region (OCR)\n⌃⌥⌘L — live translation"))
                .font(.callout).foregroundStyle(.secondary)
            if let issue = coordinator.hotkeyIssue { Text(issue).foregroundStyle(.red) }
            permission(symbol: "text.cursor", title: String(localized: "Selected text"),
                       detail: String(localized: "Accessibility"), granted: coordinator.accessibilityGranted) { coordinator.requestAccessibility() }
            permission(symbol: "viewfinder", title: String(localized: "Screen region and Live"),
                       detail: String(localized: "Screen & System Audio Recording"), granted: coordinator.screenGranted) { coordinator.requestScreen() }
            Text(String(localized: "Manual translation works without these permissions. If access does not appear, use “Reset and ask again” in the permissions panel."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { coordinator.refreshPermissions() }
    }

    private func permission(symbol: String, title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent {
            if granted {
                Label(String(localized: "Allowed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(String(localized: "Allow…"), action: action)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) }
            } icon: { Image(systemName: symbol) }
        }
    }
}
