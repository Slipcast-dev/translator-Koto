import Carbon

/// Carbon регистрирует только три команды; не слушает поток вводимых пользователем клавиш.
@MainActor
final class GlobalHotkeyService {
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var action: ((UInt32) -> Void)?

    func register(action: @escaping (UInt32) -> Void) -> String? {
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
        guard status == noErr else { unregister(); return "Не удалось подключить горячие клавиши." }
        // Exclusive нужен для настоящего отказа при конфликте между разными процессами.
        for (id, key) in [(UInt32(1), UInt32(kVK_ANSI_T)), (UInt32(2), UInt32(kVK_ANSI_R)), (UInt32(3), UInt32(kVK_ANSI_L))] {
            var reference: EventHotKeyRef?
            let code = RegisterEventHotKey(key, UInt32(controlKey | optionKey | cmdKey),
                EventHotKeyID(signature: 0x4B4F544F, id: id), GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive), &reference)
            guard code == noErr, let reference else {
                unregister()
                return "Сочетания ⌃⌥⌘T / ⌃⌥⌘R / ⌃⌥⌘L заняты. Освободите их в другом приложении и повторите включение."
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
