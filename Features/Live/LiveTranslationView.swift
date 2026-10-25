import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

struct LiveTranslationView: View {
    @Bindable var coordinator: LiveTranslationCoordinator
    @Bindable private var engines = EnginePreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "Live translation")).font(.title2.bold())
                Spacer()
                Text(coordinator.regionDescription).foregroundStyle(.secondary)
            }
            HStack {
                Button(String(localized: "Choose region…")) { coordinator.chooseRegion() }.buttonStyle(.borderedProminent)
                if coordinator.running {
                    Button(String(localized: "Pause")) { coordinator.pause() }
                } else {
                    Button(String(localized: "Resume")) { coordinator.resume() }.disabled(!coordinator.hasRegion)
                }
                Button(String(localized: "Stop")) { coordinator.stop() }.disabled(!coordinator.hasRegion)
                Spacer()
            }
            Picker(String(localized: "Engine"), selection: $engines.selected) {
                ForEach(TranslationEngineKind.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            LanguageSelectionView(model: coordinator.model)
            Text(coordinator.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            HStack(alignment: .top, spacing: 18) {
                ScrollView {
                    Text(coordinator.model.sourceText.isEmpty ? String(localized: "Recognized text will appear here") : coordinator.model.sourceText)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, AppLocalization.isRightToLeft(language: coordinator.model.sourceIdentifier, text: coordinator.model.sourceText) ? .rightToLeft : .leftToRight)
                }
                TranslationOutputView(result: coordinator.model.result)
            }.frame(minHeight: 220)
            TranslationStatusView(model: coordinator.model)
            HStack {
                Text(String(localized: "Frames: \(AppLocalization.number(coordinator.captures)) · Translations: \(AppLocalization.number(coordinator.translations))"))
                if let p50 = coordinator.p50, let p95 = coordinator.p95 {
                    Text(String(localized: "p50 \(AppLocalization.number(Int(p50))) ms · p95 \(AppLocalization.number(Int(p95))) ms"))
                }
                Spacer()
            }.font(.caption).foregroundStyle(.secondary)
            Text(String(localized: "Only the selected region is recognized. Koto windows are excluded from capture. Frames and text are not saved; metric history is limited to 120 values."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(minWidth: 760, minHeight: 530)
        .onChange(of: engines.selected) { _, _ in coordinator.engineChanged() }
        .onChange(of: coordinator.model.result?.requestID) { _, _ in coordinator.didPublish() }
        .onChange(of: coordinator.model.sourceIdentifier) { _, _ in coordinator.translationOptionsChanged() }
        .onChange(of: coordinator.model.targetIdentifier) { _, _ in coordinator.translationOptionsChanged() }
        .sheet(item: Binding(get: { coordinator.model.preparation },
                             set: { if $0 == nil { coordinator.model.dismissPreparation() } })) { ticket in
            LanguagePreparationView(ticket: ticket) { id, error in
                coordinator.model.finishPreparation(id: id, failure: error)
            }
        }
        .onDisappear { coordinator.stop() }
        .accessibilityIdentifier("koto.live")
    }
}
