import SwiftUI

/// State живёт в app coordinator, поэтому закрытие окна не теряет маршрут глобальных команд.
struct MainWindowView: View {
    let coordinator: CaptureCoordinator
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Перевести выделение") { coordinator.captureSelection() }
                    .help("Выделите текст в другом приложении и нажмите ⌃⌥⌘T")
                Button("Область экрана…") { coordinator.captureRegion() }
                    .help("Выбрать область с текстом · ⌃⌥⌘R")
                if coordinator.captureBusy {
                    Button("Отменить захват") { coordinator.cancel() }
                }
                Spacer()
            }.padding(.horizontal, 28).padding(.top, 12)
            ManualTranslationView(model: coordinator.manualModel)
        }
    }
}
