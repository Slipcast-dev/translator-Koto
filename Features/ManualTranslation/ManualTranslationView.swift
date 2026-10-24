import AppKit
import SwiftUI

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
                Text("Перевод текста").foregroundStyle(.secondary)
            }
            if let issue = model.catalogFailure {
                HStack {
                    Text(issue).foregroundStyle(.red)
                    Button("Повторить") { Task { await model.loadLanguages() } }
                }
            }
            Picker("Движок", selection: $engines.selected) {
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
                Button("Объяснение и варианты · локально") { showInsights = true }
                    .disabled(model.sourceText.isEmpty || model.sourceText.count > 500)
                    .help("Смысл, выражения и варианты перевода: до 500 символов")
                Text(SpeechController.shared.status).font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if model.isBusy {
                    Button("Отменить") { model.cancel() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .accessibilityIdentifier("translation.cancel")
                } else {
                    Button("Перевести") { model.submit() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!model.canTranslate)
                        .accessibilityIdentifier("translation.submit")
                }
                Button(copied ? "Скопировано" : "Копировать") { copyResult() }
                    .disabled(model.result == nil)
                    .accessibilityIdentifier("translation.copy")
                Button("Очистить") { model.clear() }
                    .disabled(model.sourceText.isEmpty && model.result == nil)
                    .accessibilityIdentifier("translation.clear")
                Button("Озвучить") { if let result = model.result { SpeechController.shared.speak(result) } }
                    .disabled(model.result == nil)
                Button("Стоп") { SpeechController.shared.stop() }
                Spacer()
                Text(ProductInfo.versionDescription).font(.caption).foregroundStyle(.secondary)
            }
            Text(copyFailed ? "Не удалось записать текст в буфер обмена." : (TranslationStore.shared.memoryEnabled ? "Память ручных переводов включена в настройках." : "Память переводов выключена."))
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
                    .help("Настройки Koto").accessibilityLabel("Настройки Koto")
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
