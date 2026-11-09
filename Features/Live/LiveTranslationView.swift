import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Живой перевод в три шага: выбрать область, подождать, читать перевод. Без доступа к экрану
/// окно само показывает панель разрешений и продолжает после их выдачи.
struct LiveTranslationView: View {
    @Bindable var coordinator: LiveTranslationCoordinator
    let capture: CaptureCoordinator
    @Bindable private var engines = EnginePreferences.shared
    
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
        .padding(24).frame(minWidth: 680, minHeight: 460)
        .task { capture.refreshPermissions(); if !capture.screenGranted { capture.waitForPermission(for: .live) } }
        .onChange(of: engines.selected) { _, _ in coordinator.engineChanged() }
        .onChange(of: coordinator.model.sourceIdentifier) { _, _ in coordinator.translationOptionsChanged() }
        .onChange(of: coordinator.model.targetIdentifier) { _, _ in coordinator.translationOptionsChanged() }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if coordinator.running {
                    Button { coordinator.pause() } label: { Label(String(localized: "Pause"), systemImage: "pause.fill") }
                } else {
                    Button { coordinator.resume() } label: { Label(String(localized: "Resume"), systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                }
                Button { coordinator.chooseRegion() } label: { Label(String(localized: "Another region…"), systemImage: "viewfinder") }
                Button(role: .destructive) { coordinator.stop() } label: { Label(String(localized: "Stop"), systemImage: "stop.fill") }
                Spacer(minLength: 0)
            }
            .labelStyle(.titleAndIcon).lineLimit(1).fixedSize(horizontal: false, vertical: true)
            LanguageSelectionView(model: coordinator.model)
            Picker(String(localized: "Mode"), selection: $coordinator.mode) {
                Text(String(localized: "Replace text in place")).tag(LiveTranslationCoordinator.Mode.inPlace)
                Text(String(localized: "Word under the cursor")).tag(LiveTranslationCoordinator.Mode.hover)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
            Text(coordinator.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Text(String(localized: "The translation is drawn over the other app. Stop it here or from the Koto menu in the menu bar. Nothing is saved."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
