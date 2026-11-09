import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Сообщения об обновлении в главном окне: предложение, ход подготовки и вопрос о перезапуске.
/// Установка начинается только по кнопке «Установить»; перезапуск — только по согласию, есть «Позже».
struct UpdatePrompts: ViewModifier {
    @Bindable private var model = UpdateModel.shared

    private var offered: Binding<AppRelease?> {
        Binding(get: { if case .available(let release) = model.pendingPrompt { release } else { nil } },
                set: { if $0 == nil, case .available = model.pendingPrompt { model.dismissPrompt() } })
    }
    private var restartRelease: AppRelease? { if case .restart(let release) = model.pendingPrompt { release } else { nil } }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { UpdateBanner(model: model) }
            .sheet(item: offered) { release in UpdateOfferView(release: release, model: model) }
            .alert(String(localized: "Restart Koto to finish the update"),
                   isPresented: Binding(get: { restartRelease != nil }, set: { if !$0 { model.dismissPrompt() } }),
                   presenting: restartRelease) { _ in
                Button(String(localized: "Restart now")) { model.restartNow() }
                Button(String(localized: "Later"), role: .cancel) { model.dismissPrompt() }
            } message: { release in
                Text(String(localized: "Version \(release.version.display) is ready. Koto will restart to apply it. If you choose Later, the update is applied when you quit Koto."))
            }
    }
}

extension View {
    func kotoUpdatePrompts() -> some View { modifier(UpdatePrompts()) }
}

/// Узкая полоса сверху: прогресс подготовки в фоне и напоминание, пока перезапуск отложен.
private struct UpdateBanner: View {
    let model: UpdateModel

    var body: some View {
        switch model.phase {
        case .downloading, .verifying, .installing:
            bar {
                ProgressView().controlSize(.small)
                Text(model.statusText)
                if model.phase == .downloading { Text("\(Int(model.progress * 100)) %").monospacedDigit().foregroundStyle(.secondary) }
                Spacer()
                Button(String(localized: "Cancel")) { model.cancel() }.buttonStyle(.link)
            }
        case .readyToRestart:
            if model.pendingPrompt == nil {
                bar {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(model.statusText).lineLimit(1)
                    Spacer()
                    Button(String(localized: "Restart now")) { model.restartNow() }.controlSize(.small)
                }
            }
        default: EmptyView()
        }
    }

    private func bar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
    }
}

/// Окно предложения: версия, описание и три выбора. Загрузка начнётся только после «Установить».
struct UpdateOfferView: View {
    let release: AppRelease
    let model: UpdateModel

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
            Text(String(localized: "Koto downloads and verifies the update in the background and keeps working. You will be asked before it restarts."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link(String(localized: "Release page"), destination: release.page)
                Spacer()
                Button(String(localized: "Skip")) { model.skip(release) }.help(String(localized: "Do not offer this version at launch"))
                Button(String(localized: "Later")) { model.dismissPrompt() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Install")) { model.install(release) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}
