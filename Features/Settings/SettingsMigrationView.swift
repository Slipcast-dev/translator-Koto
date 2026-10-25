import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

struct SettingsMigrationView: View {
    let model: ManualTranslationModel
    @State private var preview: SettingsMigration?
    @State private var message = ""
    var body: some View {
        Section(String(localized: "Transfer settings")) {
            Text(String(localized: "Only the theme and languages from Koto JSON are transferred. Keys, TCC permissions, history and Lingo files are not imported.")).font(.caption)
            HStack {
                Button(String(localized: "Export…")) { export() }
                Button(String(localized: "Read JSON…")) { read() }
            }
            if let preview {
                Text(String(localized: "Theme: \(AppAppearance.resolve(preview.appearance).title); languages: \(preview.source == "auto" ? String(localized: "Detect language") : TranslationLanguage(id: preview.source).displayName) → \(TranslationLanguage(id: preview.target).displayName)"))
                Button(String(localized: "Apply previewed settings")) {
                    guard model.languages.contains(where: { $0.id == preview.target }),
                          preview.source == "auto" || model.languages.contains(where: { $0.id == preview.source }) else {
                        message = String(localized: "This pair is not in the current engine’s catalog"); return
                    }
                    UserDefaults.standard.set(preview.appearance,forKey:"appearance")
                    model.sourceIdentifier = preview.source; model.targetIdentifier = preview.target
                    self.preview = nil; message = String(localized: "Settings applied")
                }
                Button(String(localized: "Cancel import")) { self.preview = nil }
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
            preview = try SettingsMigration.parse(Data(contentsOf:url)); message = String(localized: "Review the preview")
        } catch { message = String(localized: "Format rejected: Koto schema 1 JSON is required, with no extra fields") }
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Koto-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let settings = SettingsMigration(schema:1,appearance:UserDefaults.standard.string(forKey:"appearance") ?? "system",
                source:model.sourceIdentifier,target:model.targetIdentifier)
            try JSONEncoder().encode(settings).write(to:url,options:.atomic); message = String(localized: "Settings exported")
        } catch { message = String(localized: "Unable to save settings") }
    }
}
