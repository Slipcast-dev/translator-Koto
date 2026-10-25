import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// В menu bar только работающие команды; будущие функции не имитируются.
struct KotoMenuView: View {
    let capture: CaptureCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(String(localized: "Translate selection  ⌃⌥⌘T")) { capture.captureSelection() }
        Button(String(localized: "Translate screen region…  ⌃⌥⌘R")) { capture.captureRegion() }
            Button(String(localized: "Live translation…  ⌃⌥⌘L")) { openWindow(id: WindowID.live); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button(String(localized: "Open Koto")) {
            openWindow(id: WindowID.main)
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(String(localized: "Settings…")) {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(String(localized: "About Koto")) {
            openWindow(id: WindowID.about)
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button(String(localized: "Quit Koto")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
