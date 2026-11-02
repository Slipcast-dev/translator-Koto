import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

extension UpdateModel {
    /// Завершение приложения нужно только для перезапуска после замены bundle.
    static let shared = UpdateModel(terminate: { NSApp.terminate(nil) })
}

/// Верхний раздел настроек: версия, описание, проверка и установка обновления.
struct UpdateSettingsView: View {
    @Bindable private var model = UpdateModel.shared
    @State private var offered: AppRelease?

    var body: some View {
        Section(String(localized: "Update")) {
            LabeledContent(String(localized: "Version"), value: "\(ProductInfo.version) (\(ProductInfo.build))")
            Text(String(localized: "Koto is a native macOS translator: text, selections and screen regions, local engines and a Chrome extension."))
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "Check for updates")) { model.check() }
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("update.check")
                if model.isBusy {
                    ProgressView().controlSize(.small)
                    Button(String(localized: "Cancel")) { model.cancel() }
                }
                Spacer()
            }
            if model.phase == .downloading { ProgressView(value: model.progress) }
            Text(model.statusText).font(.caption).foregroundStyle(model.isFailed ? Color.red : Color.secondary)
                .textSelection(.enabled)
            if model.isFailed, let release = model.failedRelease {
                Link(String(localized: "Open the release page"), destination: release.page).font(.caption)
            }
            if case .available(let release) = model.phase {
                Button(String(localized: "Show update…")) { offered = release }
            }
        }
        // Меню обновления появляется само, как только проверка нашла новую версию.
        .onChange(of: model.phase) { _, phase in
            if case .available(let release) = phase { offered = release }
        }
        .sheet(item: $offered) { release in
            UpdateOfferView(release: release, model: model) { offered = nil }
        }
    }
}

private struct UpdateOfferView: View {
    let release: AppRelease
    let model: UpdateModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Update available")).font(.title2.bold())
            LabeledContent(String(localized: "New version"), value: release.version.display)
            LabeledContent(String(localized: "Installed"), value: model.currentDescription)
            LabeledContent(String(localized: "Download size"), value: AppLocalization.bytes(release.dmg.size))
            ScrollView {
                Text(release.notes.isEmpty ? release.title : release.notes)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(height: 150)
            .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            if model.isBusy {
                if model.phase == .downloading { ProgressView(value: model.progress) } else { ProgressView() }
            }
            Text(model.statusText).font(.caption).foregroundStyle(model.isFailed ? Color.red : Color.secondary)
            Text(String(localized: "The update is downloaded, verified against the release checksums and installed automatically. Koto restarts once to finish."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link(String(localized: "Release page"), destination: release.page)
                Spacer()
                Button(String(localized: "Later")) { model.cancel(); close() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Install and restart")) { model.install(release) }
                    .buttonStyle(.borderedProminent).disabled(model.isBusy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

extension UpdateModel {
    var isFailed: Bool { if case .failed = phase { true } else { false } }
}
