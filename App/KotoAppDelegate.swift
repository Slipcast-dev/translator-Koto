import AppKit

/// AppKit ограничен активацией и Dock reopen; содержимым окон управляют SwiftUI-сцены.
@MainActor
final class KotoAppDelegate: NSObject, NSApplicationDelegate {
    var reopenMainWindow: (() -> Void)?
    weak var capture: CaptureCoordinator?

    func applicationWillTerminate(_ notification: Notification) {
        capture?.stop()
        // Мост и локальный движок убирают токены и ключи с диска; память переводов дописывается до выхода.
        BrowserBridgeServer.shared.stop()
        LocalRuntimeSupervisor.shared.stop()
        TranslationStore.shared.flush()
        // Отложенное обновление («Позже») применяется при выходе: помощник заменит bundle после завершения процесса.
        UpdateModel.shared.applyOnQuit()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // MenuBarExtra не должен превращать обычное приложение в скрытый menu-only процесс.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Помощник обновления ждёт это подтверждение, прежде чем удалить прежнюю копию.
        UpdateInstaller.confirmLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // После закрытия окна пользователь сохраняет доступ через Dock и значок строки меню.
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        reopenMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
