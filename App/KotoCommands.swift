import SwiftUI

/// Меню приложения использует те же scene IDs, что и экранные кнопки и menu bar.
struct KotoCommands: Commands {
    let capture: CaptureCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Перевод") {
            Button("Перевести выделение  ⌃⌥⌘T") { capture.captureSelection() }
            Button("Перевести область…  ⌃⌥⌘R") { capture.captureRegion() }
            Button("Живой перевод…  ⌃⌥⌘L") { openWindow(id: WindowID.live); NSApp.activate(ignoringOtherApps: true) }
            Button("Отменить захват") { capture.cancel() }.disabled(!capture.captureBusy)
        }
        CommandGroup(replacing: .appInfo) {
            Button("О Koto") {
                openWindow(id: WindowID.about)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        CommandGroup(after: .appSettings) {
            Button("Открыть Koto") {
                openWindow(id: WindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
