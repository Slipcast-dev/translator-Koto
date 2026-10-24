import AppKit
import SwiftUI

struct SettingsMigrationView: View {
    let model: ManualTranslationModel
    @State private var preview: SettingsMigration?
    @State private var message = ""
    var body: some View {
        Section("Перенос настроек") {
            Text("Переносятся только тема и языки из JSON Koto. Ключи, TCC, история и файлы Lingo не импортируются.").font(.caption)
            HStack {
                Button("Экспорт…") { export() }
                Button("Прочитать JSON…") { read() }
            }
            if let preview {
                Text("Тема: \(preview.appearance); языки: \(preview.source) → \(preview.target)")
                Button("Применить показанные настройки") {
                    guard model.languages.contains(where: { $0.id == preview.target }),
                          preview.source == "auto" || model.languages.contains(where: { $0.id == preview.source }) else {
                        message = "Пара отсутствует в каталоге текущего движка"; return
                    }
                    UserDefaults.standard.set(preview.appearance,forKey:"appearance")
                    model.sourceIdentifier = preview.source; model.targetIdentifier = preview.target
                    self.preview = nil; message = "Настройки применены"
                }
                Button("Отмена импорта") { self.preview = nil }
            }
            if !message.isEmpty { Text(message).font(.caption) }
        }
    }
    private func read() {
        preview = nil
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
            guard size <= 65_536 else { throw CocoaError(.fileReadCorruptFile) }
            preview = try SettingsMigration.parse(Data(contentsOf:url)); message = "Проверьте предварительный просмотр"
        } catch { message = "Формат отклонён: нужен JSON Koto schema 1 без дополнительных полей" }
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Koto-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let settings = SettingsMigration(schema:1,appearance:UserDefaults.standard.string(forKey:"appearance") ?? "system",
                source:model.sourceIdentifier,target:model.targetIdentifier)
            try JSONEncoder().encode(settings).write(to:url,options:.atomic); message = "Настройки экспортированы"
        } catch { message = "Не удалось сохранить настройки" }
    }
}
