import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

struct ProductSettingsView: View {
    @AppStorage("privacy.cloud.capture") private var cloudCapture = false
    @AppStorage("privacy.cloud.browser") private var cloudBrowser = false
    @AppStorage("privacy.cloud.live") private var cloudLive = false
    @AppStorage("privacy.excludedApps") private var excluded = "com.apple.mail\ncom.apple.MobileSMS\nru.keepcoder.Telegram\nnet.whatsapp.WhatsApp\ncom.viber.osx"
    @AppStorage("privacy.excludedHosts") private var excludedHosts = ""
    @Bindable private var store = TranslationStore.shared
    @State private var provider = CloudTranslationEngine.Provider.google
    @State private var key = ""
    @State private var message = ""
    @State private var input = ""
    @State private var output = ""
    @State private var source = "en"
    @State private var target = "ru"
    @State private var login = ProductUtilities.loginEnabled
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
                    do { try ProviderKeychain.save(key, provider: provider.rawValue); key = ""; message = String(localized: "Key saved to Keychain") }
                    catch { message = String(localized: "Unable to save the key to Keychain") }
                }.disabled(key.isEmpty)
                Button(String(localized: "Remove key")) {
                    do { try ProviderKeychain.remove(provider.rawValue); key = ""; message = String(localized: "Key removed") }
                    catch { message = String(localized: "Unable to remove the key") }
                }
            }
        }
        Section(String(localized: "Capture privacy")) {
            Toggle(String(localized: "Allow selection and OCR in the cloud"), isOn: $cloudCapture)
            Toggle(String(localized: "Allow browser text in the cloud"), isOn: $cloudBrowser)
            Toggle(String(localized: "Allow live translation in the cloud"), isOn: $cloudLive)
            Text(String(localized: "All three sources are translated locally by default. Excluded apps are blocked for Accessibility capture and excluded from screenshots.")).font(.caption)
            TextField(String(localized: "Excluded bundle IDs, one per line"), text: $excluded, axis: .vertical).lineLimit(3...6)
            TextField(String(localized: "Excluded browser domains"), text: $excludedHosts, axis: .vertical).lineLimit(2...4)
            Text(String(localized: "A domain exclusion also covers its subdomains. The bridge receives only the page origin, without the path or query.")).font(.caption)
        }
        Section(String(localized: "Exact phrases")) {
            TextField(String(localized: "Source phrase"), text: $input)
            TextField(String(localized: "Your translation"), text: $output)
            HStack { TextField(String(localized: "Source: en"), text: $source); TextField(String(localized: "Target: ru"), text: $target) }
            Button(String(localized: "Add phrase")) { store.add(input: input, output: output, source: source, target: target) }
            ForEach(store.glossary) { record in
                HStack {
                    Text("\(record.source) → \(record.target): \(record.input) → \(record.output)").lineLimit(2)
                    Spacer(); Button(String(localized: "Remove")) { store.remove(record.id) }
                }
            }
            Text(String(localized: "Applies only to an exact match of the entire phrase and an explicitly selected language pair.")).font(.caption)
        }
        Section(String(localized: "Memory and system")) {
            Toggle(String(localized: "Save manual translations on this Mac"), isOn: $store.memoryEnabled)
            Text(String(localized: "Up to 500 phrases. Capture, browser and Live text are not saved. Turning memory off clears it.")).font(.caption)
            Button(AppLocalization.clearMemoryLabel(store.memory.count)) { store.clearMemory() }
            Toggle(String(localized: "Launch at login"), isOn: Binding(get: { login }, set: { value in
                do { try ProductUtilities.setLogin(value); login = ProductUtilities.loginEnabled
                    message = login == value ? String(localized: "Login setting updated") : String(localized: "Complete authorization in macOS Settings") }
                catch { message = String(localized: "Unable to change launch at login. Check macOS Settings.") }
            }))
            Button(String(localized: "Export diagnostics…")) {
                do { try ProductUtilities.exportDiagnostics() } catch { message = String(localized: "Unable to export diagnostics") }
            }
            if !store.status.isEmpty { Text(store.status).font(.caption) }
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
        }
        .onChange(of: provider) { _, _ in key = "" }
    }
}
