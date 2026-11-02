import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Пошаговая справка по получению ключа облачного провайдера. Ссылки открываются только по клику.
struct APIKeyFAQView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var provider: CloudTranslationEngine.Provider

    init(provider: CloudTranslationEngine.Provider) { _provider = State(initialValue: provider) }

    private struct Step: Identifiable {
        let id: Int
        let text: String
        var link: (title: String, url: URL)?
    }

    private var steps: [Step] {
        let raw: [(String, (String, String)?)] = provider == .google ? [
            (String(localized: "Sign in to Google Cloud Console and create a project (or choose an existing one)."),
             (String(localized: "Open Google Cloud Console"), "https://console.cloud.google.com/")),
            (String(localized: "Link a billing account to the project. Cloud Translation requires billing; a free monthly quota applies."), nil),
            (String(localized: "Open the Cloud Translation API page and click Enable. Koto uses Basic (v2)."),
             (String(localized: "Open Cloud Translation API"), "https://console.cloud.google.com/apis/library/translate.googleapis.com")),
            (String(localized: "Go to APIs & Services → Credentials → Create credentials → API key."),
             (String(localized: "Open Credentials"), "https://console.cloud.google.com/apis/credentials")),
            (String(localized: "Recommended: choose Restrict key, select Cloud Translation API under API restrictions and save."), nil),
            (String(localized: "Copy the key. In Koto choose “Google Cloud Basic v2” as the key provider, paste it into “New API key” and click Save to Keychain."), nil),
            (String(localized: "Choose Google Cloud as the engine in the main window. The key is stored only in the macOS Keychain; Remove key deletes it."), nil),
        ] : [
            (String(localized: "Sign in to Yandex Cloud Console. Create a cloud and a folder if you do not have them, and link a billing account."),
             (String(localized: "Open Yandex Cloud Console"), "https://console.yandex.cloud/")),
            (String(localized: "In the folder, open Service accounts and create a service account."), nil),
            (String(localized: "Grant the service account the role ai.translate.user on the folder (Access bindings)."), nil),
            (String(localized: "Open the service account, click Create new key → Create API key. If asked for a scope, choose yc.ai.translate.execute."), nil),
            (String(localized: "Copy the secret key immediately: it is shown only once."), nil),
            (String(localized: "In Koto choose “Yandex · service account API key”, paste the key into “New API key” and click Save to Keychain."), nil),
            (String(localized: "Choose Yandex Cloud as the engine in the main window. The key is stored only in the macOS Keychain."),
             (String(localized: "Yandex Translate documentation"), "https://yandex.cloud/en/docs/translate/")),
        ]
        return raw.enumerated().map { index, item in
            var link: (title: String, url: URL)?
            if let pair = item.1, let url = URL(string: pair.1) { link = (pair.0, url) }
            return Step(id: index + 1, text: item.0, link: link)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "How to get an API key")).font(.title2.bold())
            Picker(String(localized: "Key provider"), selection: $provider) {
                Text("Google Cloud Basic v2").tag(CloudTranslationEngine.Provider.google)
                Text(String(localized: "Yandex · service account API key")).tag(CloudTranslationEngine.Provider.yandex)
            }
            .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(step.id)").font(.headline).monospacedDigit()
                                .frame(width: 24, height: 24).background(.quaternary, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.text).fixedSize(horizontal: false, vertical: true)
                                if let link = step.link { Link(link.title, destination: link.url).font(.callout) }
                            }
                        }
                    }
                    Text(String(localized: "Provider consoles change over time: if a button is named differently, check the provider’s documentation. Pricing and quotas are set by your provider account; Koto never receives or stores your key outside the Keychain."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button(String(localized: "Close")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(22)
        .frame(width: 520, height: 540)
    }
}
