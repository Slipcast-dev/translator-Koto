import SwiftUI

/// Переключатели управляют реальной регистрацией, а права запрашиваются только явными кнопками.
struct CaptureSettingsView: View {
    @Bindable var coordinator: CaptureCoordinator
    var body: some View {
        Section("Перевод из других приложений") {
            Toggle("Глобальные горячие клавиши", isOn: $coordinator.hotkeysEnabled)
            Text("⌃⌥⌘T — выделенный текст\n⌃⌥⌘R — область экрана (OCR)\n⌃⌥⌘L — живой перевод")
                .font(.callout).foregroundStyle(.secondary)
            if let issue = coordinator.hotkeyIssue { Text(issue).foregroundStyle(.red) }
            Text("Резервный путь: в исходном приложении выберите «Службы → Перевести в Koto». Системная служба передаёт только выбранный текст и не меняет общий буфер обмена.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Доступ к выделению") { coordinator.requestAccessibility() }
                Button("Доступ к экрану") { coordinator.requestScreen() }
                Button("Проверить") { coordinator.refreshPermissions() }
            }
            Text("Выделение: \(coordinator.accessibilityGranted ? "доступ есть" : "нет доступа") · Экран: \(coordinator.screenGranted ? "доступ есть" : "нет доступа")")
                .font(.caption)
            Text("Для ручного перевода эти разрешения не нужны. После изменения доступа может потребоваться перезапуск Koto.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { coordinator.refreshPermissions() }
    }
}
