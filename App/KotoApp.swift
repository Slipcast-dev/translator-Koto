import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Сцены разделены по назначению: это даёт нативные меню и независимый жизненный цикл окон.
@main
struct KotoApp: App {
    @NSApplicationDelegateAdaptor(KotoAppDelegate.self) private var appDelegate
    @State private var capture = CaptureCoordinator()

    var body: some Scene {
        // Единственное главное окно повторно открывается через openWindow без создания дубликатов.
        // Явный launch behavior нужен, поскольку приложение одновременно имеет MenuBarExtra.
        Window("Koto", id: WindowID.main) {
            MainWindowView(coordinator: capture)
                .kotoAppearance()
                .background(MainWindowActionInstaller(appDelegate: appDelegate, capture: capture))
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 960, height: 690)
        .windowResizability(.contentMinSize)
        .commands { KotoCommands(capture: capture) }

        Window(String(localized: "Live translation — Koto"), id: WindowID.live) {
            LiveTranslationView(coordinator: capture.live).kotoAppearance()
        }
        .defaultSize(width: 900, height: 650)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(capture: capture)
                .kotoAppearance()
        }

        // Английский ключ служит резервным текстом; перевод заголовка берётся из каталога.
        Window("About Koto", id: WindowID.about) {
            AboutView()
                .kotoAppearance()
        }
        .defaultSize(width: 390, height: 430)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra {
            KotoMenuView(capture: capture)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("Koto")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// OpenWindowAction принадлежит SwiftUI environment; мост передаёт делегату только команду.
/// Удержание этой команды позволяет вновь открыть окно даже после уничтожения его содержимого.
private struct MainWindowActionInstaller: View {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: KotoAppDelegate
    let capture: CaptureCoordinator

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear {
                capture.start()
                appDelegate.capture = capture
                capture.reopenMain = { openWindow(id: WindowID.main) }
                capture.openLive = { openWindow(id: WindowID.live); NSApp.activate(ignoringOtherApps: true) }
                appDelegate.reopenMainWindow = {
                    openWindow(id: WindowID.main)
                }
            }
    }
}
