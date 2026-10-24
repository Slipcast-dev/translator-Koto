import SwiftUI

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
        Section("Облачный перевод") {
            Text("Ручной текст отправляется выбранному Google/Yandex Cloud по кнопке «Перевести». Тариф и квоту определяет ваш аккаунт провайдера.").font(.caption)
            Picker("Провайдер ключа", selection: $provider) {
                Text("Google Cloud Basic v2").tag(CloudTranslationEngine.Provider.google)
                Text("Yandex · API-ключ сервисного аккаунта").tag(CloudTranslationEngine.Provider.yandex)
            }
            SecureField("Новый API-ключ", text: $key)
            HStack {
                Button("Сохранить в Keychain") {
                    do { try ProviderKeychain.save(key, provider: provider.rawValue); key = ""; message = "Ключ сохранён в Keychain" }
                    catch { message = "Не удалось сохранить ключ в Keychain" }
                }.disabled(key.isEmpty)
                Button("Удалить ключ") {
                    do { try ProviderKeychain.remove(provider.rawValue); key = ""; message = "Ключ удалён" }
                    catch { message = "Не удалось удалить ключ" }
                }
            }
        }
        Section("Приватность захвата") {
            Toggle("Разрешить выделение и OCR в облаке", isOn: $cloudCapture)
            Toggle("Разрешить текст браузера в облаке", isOn: $cloudBrowser)
            Toggle("Разрешить живой перевод в облаке", isOn: $cloudLive)
            Text("По умолчанию все три источника переводятся только локально. Исключённые приложения блокируются для AX и исключаются из снимков.").font(.caption)
            TextField("Bundle ID исключений, по одному в строке", text: $excluded, axis: .vertical).lineLimit(3...6)
            TextField("Исключённые домены браузера", text: $excludedHosts, axis: .vertical).lineLimit(2...4)
            Text("Домен исключает и его поддомены. Мост получает только origin страницы, без пути и query.").font(.caption)
        }
        Section("Словарь точных фраз") {
            TextField("Исходная фраза", text: $input)
            TextField("Ваш перевод", text: $output)
            HStack { TextField("Источник: en", text: $source); TextField("Перевод: ru", text: $target) }
            Button("Добавить фразу") { store.add(input: input, output: output, source: source, target: target) }
            ForEach(store.glossary) { record in
                HStack {
                    Text("\(record.source) → \(record.target): \(record.input) → \(record.output)").lineLimit(2)
                    Spacer(); Button("Удалить") { store.remove(record.id) }
                }
            }
            Text("Применяется при точном совпадении всей фразы и явно выбранной пары языков.").font(.caption)
        }
        Section("Память и система") {
            Toggle("Сохранять ручные переводы на этом Mac", isOn: $store.memoryEnabled)
            Text("До 500 фраз. Захват, браузер и Live не сохраняются. При выключении память очищается.").font(.caption)
            Button("Очистить память (\(store.memory.count))") { store.clearMemory() }
            Toggle("Запускать при входе", isOn: Binding(get: { login }, set: { value in
                do { try ProductUtilities.setLogin(value); login = ProductUtilities.loginEnabled
                    message = login == value ? "Автозапуск обновлён" : "Завершите разрешение в настройках macOS" }
                catch { message = "Не удалось изменить автозапуск. Проверьте настройки macOS." }
            }))
            Button("Экспортировать диагностику…") {
                do { try ProductUtilities.exportDiagnostics() } catch { message = "Не удалось экспортировать диагностику" }
            }
            if !store.status.isEmpty { Text(store.status).font(.caption) }
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
        }
        .onChange(of: provider) { _, _ in key = "" }
    }
}
