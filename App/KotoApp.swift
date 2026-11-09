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
                .kotoUpdatePrompts()
                // Название «Koto» в панели инструментов не нужно: оно уже есть в заголовке содержимого.
                .toolbar(removing: .title)
                .background(MainWindowActionInstaller(appDelegate: appDelegate, capture: capture))
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 960, height: 690)
        .windowResizability(.contentMinSize)
        .commands { KotoCommands(capture: capture) }

        Window(String(localized: "Live translation — Koto"), id: WindowID.live) {
            LiveTranslationView(coordinator: capture.live, capture: capture).kotoAppearance()
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
    @Environment(\.openSettings) private var openSettings
    let appDelegate: KotoAppDelegate
    let capture: CaptureCoordinator

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            // Найденное обновление или вопрос о перезапуске показываются в главном окне: открываем его, если оно закрыто.
            .onChange(of: UpdateModel.shared.pendingPrompt) { _, prompt in
                guard prompt != nil else { return }
                openWindow(id: WindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
            .onAppear {
                capture.start()
                appDelegate.capture = capture
                capture.reopenMain = { openWindow(id: WindowID.main) }
                capture.openLive = {
                    openWindow(id: WindowID.live)
                    liveWindow()?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                // Перевод виден поверх нужного приложения, поэтому окно Koto после выбора области убирается.
                capture.live.onStarted = { liveWindow()?.orderOut(nil) }
                appDelegate.reopenMainWindow = {
                    openWindow(id: WindowID.main)
                }
                // Помощник для автоматических снимков интерфейса: открывает Settings без нажатия клавиш.
                if CommandLine.arguments.contains("--koto-open-settings") { openSettings() }
                // Те же помощники для снимков панели разрешений: запускают захват, как горячая клавиша.
                if CommandLine.arguments.contains("--koto-capture-selection") {
                    Task { @MainActor in try? await Task.sleep(for: .seconds(1.5)); capture.captureSelection() }
                }
                if CommandLine.arguments.contains("--koto-capture-region") {
                    Task { @MainActor in try? await Task.sleep(for: .seconds(1.5)); capture.captureRegion() }
                }
                // Проверка обновления при запуске: через несколько секунд, чтобы не мешать старту; молча при ошибке.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    UpdateModel.shared.checkInBackground()
                }
            }
    }
}

/// Окно живого перевода: SwiftUI даёт ему идентификатор из WindowID.
@MainActor
func liveWindow() -> NSWindow? {
    NSApp.windows.first { $0.identifier?.rawValue.contains(WindowID.live) == true }
}
