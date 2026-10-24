import AppKit
import SwiftUI

/// AppKit отвечает только за transient panel и координаты. Контент и state остаются в SwiftUI.
@MainActor
final class CaptureLensController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private weak var coordinator: CaptureCoordinator?

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 460, height: 440),
                        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "Koto · Быстрый перевод"
        panel.identifier = NSUserInterfaceItemIdentifier("koto.capture.lens")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 400, height: 330)
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: CaptureLensView(coordinator: coordinator).kotoAppearance())
        panel.delegate = self
    }

    func show(anchor: CGRect) {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor.insetBy(dx: -1, dy: -1)) })
            ?? NSScreen.main
        if let screen {
            panel.setFrame(CaptureGeometry.panelFrame(anchor: anchor, size: panel.frame.size,
                                                      visible: screen.visibleFrame), display: true)
        }
        // Панель получает клавиатурный фокус после захвата, не меняя выделение до его чтения.
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
    func windowWillClose(_ notification: Notification) { coordinator?.cancel() }
}

struct CaptureLensView: View {
    @Bindable var coordinator: CaptureCoordinator
    @State private var copied = false
    private var model: ManualTranslationModel { coordinator.lensModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(coordinator.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            if !model.sourceText.isEmpty {
                LanguageSelectionView(model: model)
                ScrollView { Text(model.sourceText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 90)
                Divider()
                TranslationOutputView(result: model.result)
                TranslationStatusView(model: model)
                HStack {
                    Button(copied ? "Скопировано" : "Копировать") {
                        guard let text = model.result?.text else { return }
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(text, forType: .string)
                    }.disabled(model.result == nil)
                    if model.isBusy {
                        Button("Отменить") { model.cancel() }
                    } else {
                        Button("Перевести") { model.submit() }.disabled(!model.canTranslate)
                    }
                    Button("В окно") { coordinator.openCapturedInMain() }
                }
            } else {
                Text("Выделение: ⌃⌥⌘T\nОбласть экрана: ⌃⌥⌘R")
                HStack {
                    Button("Доступ к выделению") { coordinator.requestAccessibility() }
                    Button("Доступ к экрану") { coordinator.requestScreen() }
                }
                Button("Проверить разрешения") { coordinator.refreshPermissions() }
                Text("Выделение: \(coordinator.accessibilityGranted ? "доступ есть" : "доступа нет") · Экран: \(coordinator.screenGranted ? "доступ есть" : "доступа нет")")
                    .font(.caption)
                Text("После выдачи доступа повторите исходную команду. Текст и изображения не сохраняются.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .onChange(of: model.result?.requestID) { _, _ in copied = false }
        .sheet(item: Binding(get: { model.preparation }, set: { if $0 == nil { model.dismissPreparation() } })) { ticket in
            LanguagePreparationView(ticket: ticket) { id, issue in model.finishPreparation(id: id, failure: issue) }
        }
        .accessibilityIdentifier("koto.capture.lens")
    }
}
