import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Облачные ключи: провайдер, поле ключа, Keychain и справка по получению ключа.
struct CloudSettingsView: View {
    @State private var provider = CloudTranslationEngine.Provider.google
    @State private var key = ""
    @State private var message = ""
    @State private var showingFAQ = false

    var body: some View {
        Section(String(localized: "Cloud translation")) {
            Text(String(localized: "Manual text is sent to the selected Google/Yandex Cloud provider when you click Translate. Your provider account determines pricing and quotas.")).font(.caption)
            Picker(String(localized: "Key provider"), selection: $provider) {
                Text("Google Cloud Basic v2").tag(CloudTranslationEngine.Provider.google)
                Text(String(localized: "Yandex · service account API key")).tag(CloudTranslationEngine.Provider.yandex)
            }
            SecureField(String(localized: "New API key"), text: $key)
            HStack {
                Button(String(localized: "Save to Keychain")) {
                    do { try ProviderKeychain.save(key, provider: provider.rawValue); key = ""; message = String(localized: "Key saved to Keychain")
                        EngineStatus.shared.keychainChanged() }
                    catch { message = String(localized: "Unable to save the key to Keychain") }
                }.disabled(key.isEmpty)
                Button(String(localized: "Remove key")) {
                    do { try ProviderKeychain.remove(provider.rawValue); key = ""; message = String(localized: "Key removed")
                        EngineStatus.shared.keychainChanged() }
                    catch { message = String(localized: "Unable to remove the key") }
                }
                Spacer()
                Button(String(localized: "FAQ: how to get a key")) { showingFAQ = true }
            }
            .sheet(isPresented: $showingFAQ) { APIKeyFAQView(provider: provider) }
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
        }
        .onChange(of: provider) { _, _ in key = "" }
    }
}

/// Приватность: что можно отправлять в облако, исключения, память и точные фразы.
struct PrivacySettingsView: View {
    @AppStorage("privacy.cloud.capture") private var cloudCapture = false
    @AppStorage("privacy.cloud.browser") private var cloudBrowser = false
    @AppStorage("privacy.cloud.live") private var cloudLive = false
    @AppStorage("privacy.excludedApps") private var excluded = TranslationPrivacy.defaultExcludedApps
    @AppStorage("privacy.excludedHosts") private var excludedHosts = TranslationPrivacy.defaultExcludedHosts
    @Bindable private var store = TranslationStore.shared
    @State private var input = ""
    @State private var output = ""
    @State private var source = "en"
    @State private var target = "ru"

    var body: some View {
        Section(String(localized: "Capture privacy")) {
            Toggle(String(localized: "Allow selection and OCR in the cloud"), isOn: $cloudCapture)
            Toggle(String(localized: "Allow browser text in the cloud"), isOn: $cloudBrowser)
            Toggle(String(localized: "Allow live translation in the cloud"), isOn: $cloudLive)
            Text(String(localized: "All three sources are translated locally by default. Excluded apps are blocked for Accessibility capture and excluded from screenshots.")).font(.caption)
        }
        Section(String(localized: "Exclusions")) {
            TextField(String(localized: "Excluded bundle IDs, one per line"), text: $excluded, axis: .vertical).lineLimit(3...6)
            TextField(String(localized: "Excluded browser domains"), text: $excludedHosts, axis: .vertical).lineLimit(2...4)
            Text(String(localized: "A domain exclusion also covers its subdomains. The bridge receives only the page origin, without the path or query.")).font(.caption)
        }
        Section(String(localized: "Memory and phrases")) {
            Toggle(String(localized: "Save manual translations on this Mac"), isOn: $store.memoryEnabled)
            Text(String(localized: "Up to 500 phrases. Capture, browser and Live text are not saved. The file is not encrypted: other apps running as you can read it. Turning memory off clears it.")).font(.caption)
            Button(AppLocalization.clearMemoryLabel(store.memory.count)) { store.clearMemory() }
            DisclosureGroup(String(localized: "Exact phrases")) {
                TextField(String(localized: "Source phrase"), text: $input)
                TextField(String(localized: "Your translation"), text: $output)
                HStack { TextField(String(localized: "Source: en"), text: $source); TextField(String(localized: "Target: ru"), text: $target) }
                Button(String(localized: "Add phrase")) { store.add(input: input, output: output, source: source, target: target) }
                HStack {
                    Button(String(localized: "Import phrases…")) { GlossaryPanels.importPhrases(into: store) }
                    Button(String(localized: "Export JSON…")) { GlossaryPanels.export(store, format: .json) }
                        .disabled(store.glossary.isEmpty)
                    Button(String(localized: "Export CSV…")) { GlossaryPanels.export(store, format: .csv) }
                        .disabled(store.glossary.isEmpty)
                }
                Text(String(localized: "CSV columns: source, target, input, output. An imported phrase replaces the same phrase with the same languages. The exported file is not encrypted."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(store.glossary) { record in
                    HStack {
                        Text("\(record.source) → \(record.target): \(record.input) → \(record.output)").lineLimit(2)
                        Spacer(); Button(String(localized: "Remove")) { store.remove(record.id) }
                    }
                }
                Text(String(localized: "Applies only to an exact match of the entire phrase and an explicitly selected language pair.")).font(.caption)
            }
            if !store.status.isEmpty { Text(store.status).font(.caption) }
        }
    }
}

/// Файлы выбирает только пользователь в системных панелях.
@MainActor
enum GlossaryPanels {
    static func importPhrases(into store: TranslationStore) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Размер проверяется до чтения: большой посторонний файл не загружается в память.
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= GlossaryExchange.maximumBytes,
              let data = try? Data(contentsOf: url) else {
            store.report(String(localized: "The file was rejected: check the format, language codes and phrase length."))
            return
        }
        store.importGlossary(data, format: url.pathExtension.lowercased() == "csv" ? .csv : .json)
    }

    static func export(_ store: TranslationStore, format: GlossaryFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Koto-phrases." + format.rawValue
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportGlossary(format).write(to: url, options: .atomic)
            store.report(String(localized: "Phrases exported"))
        } catch { store.report(String(localized: "Unable to export phrases")) }
    }
}

/// Запуск при входе в систему.
struct LoginSettingsView: View {
    @State private var login = ProductUtilities.loginEnabled
    @State private var message = ""

    var body: some View {
        Section(String(localized: "Startup")) {
            Toggle(String(localized: "Launch at login"), isOn: Binding(get: { login }, set: { value in
                do { try ProductUtilities.setLogin(value); login = ProductUtilities.loginEnabled
                    message = login == value ? String(localized: "Login setting updated") : String(localized: "Complete authorization in macOS Settings") }
                catch { message = String(localized: "Unable to change launch at login. Check macOS Settings.") }
            }))
            if !message.isEmpty { Text(message).font(.caption) }
        }
    }
}

/// Диагностика без текста, ключей и путей.
struct DiagnosticsSettingsView: View {
    @State private var message = ""

    var body: some View {
        Section(String(localized: "Diagnostics")) {
            Button(String(localized: "Export diagnostics…")) {
                do { try ProductUtilities.exportDiagnostics() } catch { message = String(localized: "Unable to export diagnostics") }
            }
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
        }
    }
}
