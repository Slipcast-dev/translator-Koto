import SwiftUI

struct LiveTranslationView: View {
    @Bindable var coordinator: LiveTranslationCoordinator
    @Bindable private var engines = EnginePreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Живой перевод").font(.title2.bold())
                Spacer()
                Text(coordinator.regionDescription).foregroundStyle(.secondary)
            }
            HStack {
                Button("Выбрать область…") { coordinator.chooseRegion() }.buttonStyle(.borderedProminent)
                if coordinator.running {
                    Button("Пауза") { coordinator.pause() }
                } else {
                    Button("Продолжить") { coordinator.resume() }.disabled(!coordinator.hasRegion)
                }
                Button("Остановить") { coordinator.stop() }.disabled(!coordinator.hasRegion)
                Spacer()
            }
            Picker("Движок", selection: $engines.selected) {
                ForEach(TranslationEngineKind.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            LanguageSelectionView(model: coordinator.model)
            Text(coordinator.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            HStack(alignment: .top, spacing: 18) {
                ScrollView {
                    Text(coordinator.model.sourceText.isEmpty ? "Здесь появится распознанный текст" : coordinator.model.sourceText)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                TranslationOutputView(result: coordinator.model.result)
            }.frame(minHeight: 220)
            TranslationStatusView(model: coordinator.model)
            HStack {
                Text("Кадров: \(coordinator.captures) · Переводов: \(coordinator.translations)")
                if let p50 = coordinator.p50, let p95 = coordinator.p95 {
                    Text("p50 \(Int(p50)) мс · p95 \(Int(p95)) мс")
                }
                Spacer()
            }.font(.caption).foregroundStyle(.secondary)
            Text("Распознаётся только выбранная область. Окна Koto исключены из снимка. Кадры и текст не сохраняются; история метрик ограничена 120 значениями.")
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
