import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Окно владеет model, а подвиды получают тот же reference state: нет независимых копий ввода/результата.
struct ManualTranslationView: View {
    @Bindable var model: ManualTranslationModel
    @Bindable private var engines = EnginePreferences.shared
    @State private var showInsights = false
    @State private var copied = false
    @State private var copyFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image("BrandMark").resizable().scaledToFit().frame(width: 42, height: 42)
                    .accessibilityHidden(true)
                Text("Koto").font(.system(size: 25, weight: .bold, design: .rounded))
                Spacer()
                Text(String(localized: "Text translation")).foregroundStyle(.secondary)
            }
            if let issue = model.catalogFailure {
                HStack {
                    Text(issue).foregroundStyle(.red)
                    Button(String(localized: "Try again")) { Task { await model.loadLanguages() } }
                }
            }
            Picker(String(localized: "Engine"), selection: $engines.selected) {
                ForEach(TranslationEngineKind.allCases) { engine in Text(engine.title).tag(engine) }
            }.pickerStyle(.segmented)
            LanguageSelectionView(model: model)
            HStack(alignment: .top, spacing: 20) {
                TranslationInputView(model: model)
                TranslationOutputView(result: model.result)
            }
            .frame(minHeight: 250)
            TranslationStatusView(model: model)
            HStack {
                Button(String(localized: "Explanation and alternatives · local")) { showInsights = true }
                    .disabled(model.sourceText.isEmpty || model.sourceText.count > 500)
                    .help(String(localized: "Meaning, expressions and translation alternatives: up to 500 characters"))
                Text(SpeechController.shared.status).font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if model.isBusy {
                    Button(String(localized: "Cancel")) { model.cancel() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .accessibilityIdentifier("translation.cancel")
                } else {
                    Button(String(localized: "Translate")) { model.submit() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!model.canTranslate)
                        .accessibilityIdentifier("translation.submit")
                }
                Button(copied ? String(localized: "Copied") : String(localized: "Copy")) { copyResult() }
                    .disabled(model.result == nil)
                    .accessibilityIdentifier("translation.copy")
                Button(String(localized: "Clear")) { model.clear() }
                    .disabled(model.sourceText.isEmpty && model.result == nil)
                    .accessibilityIdentifier("translation.clear")
                Button(String(localized: "Speak")) { if let result = model.result { SpeechController.shared.speak(result) } }
                    .disabled(model.result == nil)
                Button(String(localized: "Stop")) { SpeechController.shared.stop() }
                Spacer()
                Text(ProductInfo.versionDescription).font(.caption).foregroundStyle(.secondary)
            }
            Text(copyFailed ? String(localized: "Unable to copy text to the clipboard.") : (TranslationStore.shared.memoryEnabled ? String(localized: "Manual translation memory is enabled in Settings.") : String(localized: "Translation memory is off.")))
                .font(.caption)
                .foregroundStyle(copyFailed ? Color.red : Color.secondary)
        }
        .padding(28)
        .frame(minWidth: 760, minHeight: 580)
        .task { await model.loadLanguages() }
        .onDisappear { model.cancel(); SpeechController.shared.stop() }
        .onChange(of: engines.selected) { _, _ in
            model.clear()
            Task { await model.loadLanguages() }
        }
        .onChange(of: model.result?.requestID) { _, _ in copied = false; copyFailed = false; SpeechController.shared.stop() }
        .sheet(item: Binding(
            get: { model.preparation },
            set: { if $0 == nil { model.dismissPreparation() } }
        )) { ticket in
            LanguagePreparationView(ticket: ticket) { id, error in
                model.finishPreparation(id: id, failure: error)
            }
        }
        .sheet(isPresented: $showInsights) { LocalInsightsView(text: model.sourceText, target: model.targetIdentifier) }
        .toolbar {
            ToolbarItem {
                SettingsLink { Image(systemName: "gearshape") }
                    .help(String(localized: "Koto Settings")).accessibilityLabel(String(localized: "Koto Settings"))
            }
        }
        .accessibilityIdentifier("koto.main")
    }

    private func copyResult() {
        guard let text = model.result?.text else { return }
        // Запись только по явной кнопке; содержимое clipboard не считывается приложением.
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.setString(text, forType: .string)
        copyFailed = !copied
    }
}
