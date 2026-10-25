import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Меню приложения использует те же scene IDs, что и экранные кнопки и menu bar.
struct KotoCommands: Commands {
    let capture: CaptureCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu(String(localized: "Translation")) {
            Button(String(localized: "Translate selection  ⌃⌥⌘T")) { capture.captureSelection() }
            Button(String(localized: "Translate screen region…  ⌃⌥⌘R")) { capture.captureRegion() }
            Button(String(localized: "Live translation…  ⌃⌥⌘L")) { openWindow(id: WindowID.live); NSApp.activate(ignoringOtherApps: true) }
            Button(String(localized: "Cancel capture")) { capture.cancel() }.disabled(!capture.captureBusy)
        }
        CommandGroup(replacing: .appInfo) {
            // Команда и заголовок окна используют один ключ, чтобы подписи совпадали.
            Button("About Koto") {
                openWindow(id: WindowID.about)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        CommandGroup(after: .appSettings) {
            Button(String(localized: "Open Koto")) {
                openWindow(id: WindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
