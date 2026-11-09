import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// State живёт в app coordinator, поэтому закрытие окна не теряет маршрут глобальных команд.
/// Все кнопки находятся в панели инструментов ManualTranslationView.
struct MainWindowView: View {
    let coordinator: CaptureCoordinator
    var body: some View {
        ManualTranslationView(model: coordinator.manualModel, coordinator: coordinator)
    }
}
