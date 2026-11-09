import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Окно владеет model, а подвиды получают тот же reference state: нет независимых копий ввода/результата.
struct ManualTranslationView: View {
    @Bindable var model: ManualTranslationModel
    let coordinator: CaptureCoordinator
    @Environment(\.openWindow) private var openWindow
    @Bindable private var speech = SpeechController.shared
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
            }
            if let issue = model.catalogFailure {
                HStack {
                    Text(issue).foregroundStyle(.red)
                    Button(String(localized: "Try again")) { Task { await model.loadLanguages() } }
                }
            }
            // Отдельные кнопки с небольшим интервалом, по центру окна.
            HStack(spacing: 8) {
                ForEach(TranslationEngineKind.allCases) { engine in
                    let selected = engines.selected == engine
                    Button { engines.selected = engine } label: {
                        Text(engine.title).lineLimit(1).padding(.horizontal, 14).padding(.vertical, 6)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Color.accentColor : Color.secondary.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .contain).accessibilityLabel(String(localized: "Engine"))
            LanguageSelectionView(model: model)
            HStack(alignment: .top, spacing: 20) {
                TranslationInputView(model: model)
                TranslationOutputView(result: model.result)
                    .padding(.bottom, 44) // та же высота, что у строки кнопок под полем ввода
            }
            .frame(minHeight: 250)
            TranslationStatusView(model: model)
            HStack(spacing: 12) {
                Text(speech.status).font(.caption).foregroundStyle(.secondary)
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
        // Все действия собраны в одной панели инструментов и разделены по смыслу:
        // захват → результат → пояснение → настройки. «Перевести» и «Очистить» стоят под полем ввода.
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { coordinator.captureSelection() } label: {
                    Label(String(localized: "Selection"), systemImage: "text.cursor")
                }
                .help(String(localized: "Translate text selected in another app · ⌃⌥⌘T"))
                Button { coordinator.captureRegion() } label: {
                    Label(String(localized: "Screen region"), systemImage: "viewfinder")
                }
                .help(String(localized: "Choose a region containing text · ⌃⌥⌘R"))
                Button { coordinator.startLive() } label: {
                    Label(String(localized: "Live"), systemImage: "dot.radiowaves.left.and.right")
                }
                .help(String(localized: "Live translation of a screen region · ⌃⌥⌘L"))
                if coordinator.captureBusy {
                    Button { coordinator.cancel() } label: { Label(String(localized: "Cancel capture"), systemImage: "xmark.circle") }
                        .help(String(localized: "Cancel capture"))
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { copyResult() } label: {
                    Label(copied ? String(localized: "Copied") : String(localized: "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(model.result == nil).help(String(localized: "Copy the translation"))
                .accessibilityIdentifier("translation.copy")
                Button { if let result = model.result { speech.speak(result) } } label: {
                    Label(String(localized: "Speak"), systemImage: "speaker.wave.2")
                }
                .disabled(model.result == nil).help(String(localized: "Speak the translation"))
                Button { speech.stop() } label: { Label(String(localized: "Stop speech"), systemImage: "speaker.slash") }
                    .disabled(speech.status.isEmpty).help(String(localized: "Stop speech"))
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button { showInsights = true } label: { Label(String(localized: "Explanation"), systemImage: "text.book.closed") }
                    .disabled(model.sourceText.isEmpty || model.sourceText.count > 500)
                    .help(String(localized: "Explanation and alternatives · local · up to 500 characters"))
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label(String(localized: "Koto Settings"), systemImage: "gearshape") }
                    .help(String(localized: "Koto Settings"))
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
