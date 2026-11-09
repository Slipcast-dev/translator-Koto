import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Живой перевод в три шага: выбрать область, подождать, читать перевод. Без доступа к экрану
/// окно само показывает панель разрешений и продолжает после их выдачи.
struct LiveTranslationView: View {
    @Bindable var coordinator: LiveTranslationCoordinator
    let capture: CaptureCoordinator
    @Bindable private var engines = EnginePreferences.shared
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !capture.screenGranted {
                CapturePermissionView(coordinator: capture)
            } else if !coordinator.hasRegion {
                welcome
            } else {
                translation
            }
        }
        .padding(24).frame(minWidth: 640, minHeight: 460)
        .task { capture.refreshPermissions(); if !capture.screenGranted { capture.waitForPermission(for: .live) } }
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Live translation")).font(.title2.bold())
                Text(String(localized: "Koto watches a region of the screen and translates its text when it changes: subtitles, chats, games."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if coordinator.hasRegion { Text(coordinator.regionDescription).font(.caption).foregroundStyle(.secondary) }
        }
    }

    /// Первый шаг: одна понятная кнопка вместо набора настроек.
    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "viewfinder.rectangular").font(.system(size: 46)).foregroundStyle(.tint)
            Text(String(localized: "Choose the part of the screen with text")).font(.headline)
            Text(String(localized: "Drag a rectangle over the text. Translation starts at once. Press Esc to cancel."))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(String(localized: "Choose region…")) { coordinator.chooseRegion() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text(coordinator.message).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var translation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if coordinator.running {
                    Button { coordinator.pause() } label: { Label(String(localized: "Pause"), systemImage: "pause.fill") }
                } else {
                    Button { coordinator.resume() } label: { Label(String(localized: "Resume"), systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                }
                Button { coordinator.chooseRegion() } label: { Label(String(localized: "Another region…"), systemImage: "viewfinder") }
                Button(role: .destructive) { coordinator.stop() } label: { Label(String(localized: "Stop"), systemImage: "stop.fill") }
                Spacer()
                LanguageSelectionView(model: coordinator.model).fixedSize()
            }
            Picker(String(localized: "Mode"), selection: $coordinator.mode) {
                Text(String(localized: "Word under the cursor")).tag(LiveTranslationCoordinator.Mode.hover)
                Text(String(localized: "Whole region")).tag(LiveTranslationCoordinator.Mode.area)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
            Text(coordinator.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            if coordinator.mode == .hover {
                hoverHint
            } else {
            HStack(alignment: .top, spacing: 16) {
                column(title: String(localized: "Recognized")) {
                    ScrollView {
                        Text(coordinator.model.sourceText.isEmpty ? String(localized: "Recognized text will appear here") : coordinator.model.sourceText)
                            .foregroundStyle(coordinator.model.sourceText.isEmpty ? .tertiary : .primary)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .environment(\.layoutDirection, AppLocalization.isRightToLeft(language: coordinator.model.sourceIdentifier, text: coordinator.model.sourceText) ? .rightToLeft : .leftToRight)
                    }
                }
                TranslationOutputView(result: coordinator.model.result)
            }
            .frame(minHeight: 200)
            }
            TranslationStatusView(model: coordinator.model)
            DisclosureGroup(String(localized: "Details"), isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Frames: \(AppLocalization.number(coordinator.captures)) · Translations: \(AppLocalization.number(coordinator.translations))"))
                    if let p50 = coordinator.p50, let p95 = coordinator.p95 {
                        Text(String(localized: "p50 \(AppLocalization.number(Int(p50))) ms · p95 \(AppLocalization.number(Int(p95))) ms"))
                    }
                    Text(String(localized: "Only the selected region is recognized. Koto windows are excluded from capture. Frames and text are not saved. The engine is chosen in the main window."))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var hoverHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "cursorarrow.rays").font(.system(size: 40)).foregroundStyle(.tint)
            Text(String(localized: "Hold the cursor over a word")).font(.headline)
            Text(String(localized: "Inside the chosen region the translation appears right next to the word. Nothing is saved."))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func column<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }
}
