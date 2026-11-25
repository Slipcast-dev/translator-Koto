import Carbon

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Carbon регистрирует только три команды; не слушает поток вводимых пользователем клавиш.
@MainActor
final class GlobalHotkeyService {
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var action: ((UInt32) -> Void)?

    func register(_ bindings: [HotkeyAction: HotkeyBinding] = HotkeyPreferences.defaults,
                  action: @escaping (UInt32) -> Void) -> String? {
        unregister()
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x4B4F544F else { return OSStatus(eventNotHandledErr) }
            // ApplicationEventTarget доставляет callback в главном run loop.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotkeyService>.fromOpaque(context).takeUnretainedValue().action?(id.id)
            }
            return noErr
        }, 1, &spec, context, &handler)
        guard status == noErr else { unregister(); return String(localized: "Unable to register keyboard shortcuts.") }
        // Exclusive нужен для настоящего отказа при конфликте между разными процессами.
        for command in HotkeyAction.allCases {
            let binding = bindings[command] ?? command.defaultBinding
            var reference: EventHotKeyRef?
            let code = RegisterEventHotKey(binding.keyCode, binding.modifiers,
                EventHotKeyID(signature: 0x4B4F544F, id: command.rawValue), GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive), &reference)
            guard code == noErr, let reference else {
                unregister()
                return String(localized: "The shortcut \(binding.display) is in use. Release it in the other app or choose another one.")
            }
            registrations.append(reference)
        }
        return nil
    }

    func unregister() {
        for reference in registrations { UnregisterEventHotKey(reference) }
        registrations.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        action = nil
    }
}
