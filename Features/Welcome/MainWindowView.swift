import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// State живёт в app coordinator, поэтому закрытие окна не теряет маршрут глобальных команд.
struct MainWindowView: View {
    let coordinator: CaptureCoordinator
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(String(localized: "Translate selection")) { coordinator.captureSelection() }
                    .help(String(localized: "Select text in another app and press ⌃⌥⌘T"))
                Button(String(localized: "Screen region…")) { coordinator.captureRegion() }
                    .help(String(localized: "Choose a region containing text · ⌃⌥⌘R"))
                if coordinator.captureBusy {
                    Button(String(localized: "Cancel capture")) { coordinator.cancel() }
                }
                Spacer()
            }.padding(.horizontal, 28).padding(.top, 12)
            ManualTranslationView(model: coordinator.manualModel)
        }
    }
}
