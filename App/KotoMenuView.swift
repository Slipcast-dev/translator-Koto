import SwiftUI

/// В menu bar только работающие команды; будущие функции не имитируются.
struct KotoMenuView: View {
    let capture: CaptureCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Перевести выделение  ⌃⌥⌘T") { capture.captureSelection() }
        Button("Перевести область…  ⌃⌥⌘R") { capture.captureRegion() }
            Button("Живой перевод…  ⌃⌥⌘L") { openWindow(id: WindowID.live); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Открыть Koto") {
            openWindow(id: WindowID.main)
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Настройки…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("О Koto") {
            openWindow(id: WindowID.about)
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Выйти из Koto") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
