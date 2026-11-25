import AppKit
import Carbon
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Запись сочетания. События читаются только локальным монитором окна настроек и только во время записи.
struct ShortcutRecorderRow: View {
    let action: HotkeyAction
    let coordinator: CaptureCoordinator
    @Binding var recording: HotkeyAction?
    @Binding var message: String?
    @State private var monitor: Any?

    private var active: Bool { recording == action }

    var body: some View {
        LabeledContent(action.title) {
            Button(active ? String(localized: "Press a shortcut… Esc cancels") : coordinator.shortcut(action)) {
                if active { recording = nil } else { message = nil; recording = action }
            }
            .accessibilityIdentifier("hotkey.\(action.rawValue)")
        }
        .onChange(of: recording) { _, value in
            if value == action { start() } else { stop() }
        }
        .onDisappear {
            if active { recording = nil }
            stop()
        }
    }

    private func start() {
        stop()
        // Действующие сочетания снимаются, иначе macOS перехватит их раньше окна настроек.
        coordinator.setHotkeysSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode)
            let flags = event.modifierFlags
            let characters = event.charactersIgnoringModifiers
            MainActor.assumeIsolated { handle(keyCode: keyCode, flags: flags, characters: characters) }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func handle(keyCode: Int, flags: NSEvent.ModifierFlags, characters: String?) {
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if keyCode == kVK_Escape && modifiers == 0 { recording = nil; return }
        let binding = HotkeyBinding(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers),
                                    key: HotkeyBinding.keyName(keyCode: keyCode, characters: characters))
        if let problem = HotkeyPreferences.problem(binding, for: action, in: coordinator.bindings) {
            message = problem
            return
        }
        // Сначала возвращаются прежние регистрации, затем проверяется новое сочетание.
        stop()
        coordinator.setHotkeysSuspended(false)
        recording = nil
        message = coordinator.setHotkey(action, binding)
    }
}
