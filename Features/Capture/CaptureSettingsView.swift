import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Горячие клавиши и доступы macOS в одном месте. Права запрашиваются только кнопками «Разрешить…».
struct CaptureSettingsView: View {
    @Bindable var coordinator: CaptureCoordinator
    @State private var recording: HotkeyAction?
    @State private var shortcutMessage: String?
    @AppStorage(SelectionCaptureService.clipboardFallbackKey) private var clipboardFallback = true

    var body: some View {
        Section(String(localized: "Translate from other apps")) {
            Toggle(String(localized: "Global keyboard shortcuts"), isOn: $coordinator.hotkeysEnabled)
            ForEach(HotkeyAction.allCases) { action in
                ShortcutRecorderRow(action: action, coordinator: coordinator,
                                    recording: $recording, message: $shortcutMessage)
            }
            Button(String(localized: "Restore default shortcuts")) {
                recording = nil; shortcutMessage = nil; coordinator.resetHotkeys()
            }
            if let shortcutMessage { Text(shortcutMessage).font(.callout).foregroundStyle(.red) }
            if let issue = coordinator.hotkeyIssue { Text(issue).foregroundStyle(.red) }
            permission(symbol: "text.cursor", title: String(localized: "Selected text"),
                       detail: String(localized: "Accessibility"), granted: coordinator.accessibilityGranted) { coordinator.requestAccessibility() }
            permission(symbol: "viewfinder", title: String(localized: "Screen region and Live"),
                       detail: String(localized: "Screen & System Audio Recording"), granted: coordinator.screenGranted) { coordinator.requestScreen() }
            Toggle(String(localized: "Copy the selection with ⌘C when an app does not share it"), isOn: $clipboardFallback)
            Text(String(localized: "Koto restores the clipboard, but clipboard managers and Universal Clipboard may see the copied text. Turn this off to read selections only through Accessibility."))
                .font(.caption).foregroundStyle(.secondary)
            Text(String(localized: "Manual translation works without these permissions. If access does not appear, use “Reset and ask again” in the permissions panel."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { coordinator.refreshPermissions() }
        // Регистрации возвращает только окончание записи целиком: переход к другой строке их не включает.
        .onChange(of: recording) { _, value in if value == nil { coordinator.setHotkeysSuspended(false) } }
        .onDisappear { recording = nil; coordinator.setHotkeysSuspended(false) }
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
