import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Плавающая метка живого перевода: пока выбрана область, пользователь видит состояние и движок
/// и может остановить перевод, не открывая окно Koto. Панель не забирает фокус у приложения под ней,
/// а собственные окна Koto исключаются из снимков, поэтому метка не переводит саму себя.
@MainActor
final class LiveIndicatorController {
    private let panel: NSPanel
    private var placedFor: CGRect?
    static let size = CGSize(width: 500, height: 58)

    init(coordinator: LiveTranslationCoordinator) {
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.identifier = NSUserInterfaceItemIdentifier("koto.live.indicator")
        let hosting = NSHostingView(rootView: LiveIndicatorView(coordinator: coordinator).kotoAppearance())
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    /// Место выбирается один раз для каждой области: перетащенную пользователем метку пауза не сдвигает.
    func show(region: CGRect, screen: CGRect) {
        if placedFor != region {
            placedFor = region
            panel.setFrame(Self.frame(region: region, visible: screen), display: true)
        }
        panel.orderFrontRegardless()
    }

    func hide() { placedFor = nil; panel.orderOut(nil) }

    /// Над областью, иначе под ней, иначе у верхнего края внутри экрана.
    nonisolated static func frame(region: CGRect, visible: CGRect, size: CGSize = CGSize(width: 500, height: 58)) -> CGRect {
        var y = region.maxY + 8
        if y + size.height > visible.maxY { y = region.minY - size.height - 8 }
        if y < visible.minY { y = visible.maxY - size.height - 8 }
        let x = min(max(region.midX - size.width / 2, visible.minX + 4), visible.maxX - size.width - 4)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

struct LiveIndicatorView: View {
    let coordinator: LiveTranslationCoordinator
    @Bindable private var engines = EnginePreferences.shared

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(coordinator.running ? Color.red : Color.secondary).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(coordinator.running ? String(localized: "Live translation is on") : String(localized: "Live translation paused"))
                    .font(.callout.weight(.semibold))
                // Отправка текста с экрана в облако должна быть видна всё время работы.
                Text(engines.selected.isCloud
                     ? String(localized: "Cloud: \(engines.selected.title)")
                     : engines.selected.title)
                    .font(.caption)
                    .foregroundStyle(engines.selected.isCloud ? Color.orange : Color.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .layoutPriority(1)
            .help(engines.selected.isCloud
                  ? String(localized: "Screen text is sent to \(engines.selected.title)") + "\n" + coordinator.message
                  : coordinator.message)
            Spacer(minLength: 4)
            Button {
                if coordinator.running { coordinator.pause() } else { coordinator.resume() }
            } label: {
                Image(systemName: coordinator.running ? "pause.fill" : "play.fill")
            }
            .help(coordinator.running ? String(localized: "Pause") : String(localized: "Resume"))
            .accessibilityLabel(coordinator.running ? String(localized: "Pause") : String(localized: "Resume"))
            Button(role: .destructive) { coordinator.stop() } label: {
                // Цвет задан явно: в неактивной панели системная заметная кнопка рисуется серой.
                Label(String(localized: "Stop"), systemImage: "stop.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.red, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(width: LiveIndicatorController.size.width, height: LiveIndicatorController.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("koto.live.indicator")
    }
}
