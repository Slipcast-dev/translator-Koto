import Carbon
import Foundation

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Три глобальные команды. rawValue — идентификатор регистрации Carbon.
enum HotkeyAction: UInt32, CaseIterable, Identifiable, Sendable {
    case selection = 1, region = 2, live = 3
    var id: UInt32 { rawValue }
    var title: String {
        switch self {
        case .selection: String(localized: "Selected text")
        case .region: String(localized: "Screen region")
        case .live: String(localized: "Live translation")
        }
    }
    var defaultBinding: HotkeyBinding {
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        return switch self {
        case .selection: HotkeyBinding(keyCode: UInt32(kVK_ANSI_T), modifiers: modifiers, key: "T")
        case .region: HotkeyBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: modifiers, key: "R")
        case .live: HotkeyBinding(keyCode: UInt32(kVK_ANSI_L), modifiers: modifiers, key: "L")
        }
    }
}

/// Сочетание хранится как физическая клавиша и маска Carbon; `key` — только подпись для интерфейса.
struct HotkeyBinding: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    private static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
        kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]

    /// Глобальное сочетание не должно перехватывать обычный набор и привычные команды приложений:
    /// нужен ⌘ или ⌃ и ещё один модификатор; для функциональной клавиши достаточно ⌘ или ⌃.
    var isAcceptable: Bool {
        let primary = modifiers & UInt32(cmdKey | controlKey) != 0
        let count = [cmdKey, controlKey, optionKey, shiftKey].filter { modifiers & UInt32($0) != 0 }.count
        let function = Self.functionKeys.contains(Int(keyCode))
        return primary && (count >= 2 || function) && !key.isEmpty && key.count <= 8 && keyCode < 128
    }

    /// Буквы и цифры подписываются по латинской раскладке, чтобы подпись не зависела от текущего языка ввода.
    static func keyName(keyCode: Int, characters: String?) -> String {
        let names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
            kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
            kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19"
        ]
        if let name = names[keyCode] { return name }
        return String((characters ?? "").uppercased().prefix(1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Пользовательские сочетания. Повреждённые, небезопасные или повторяющиеся значения заменяются стандартными.
enum HotkeyPreferences {
    nonisolated static let key = "capture.hotkeys"

    static var defaults: [HotkeyAction: HotkeyBinding] {
        Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, $0.defaultBinding) })
    }

    static func load(_ store: UserDefaults = .standard) -> [HotkeyAction: HotkeyBinding] {
        guard let data = store.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data) else { return defaults }
        var result = defaults
        for action in HotkeyAction.allCases {
            if let binding = saved[String(action.rawValue)], binding.isAcceptable { result[action] = binding }
        }
        let combinations = Set(result.values.map { "\($0.keyCode)/\($0.modifiers)" })
        return combinations.count == result.count ? result : defaults
    }

    static func save(_ bindings: [HotkeyAction: HotkeyBinding], to store: UserDefaults = .standard) {
        let value = Dictionary(uniqueKeysWithValues: bindings.map { (String($0.key.rawValue), $0.value) })
        if let data = try? JSONEncoder().encode(value) { store.set(data, forKey: key) }
    }

    /// nil — сочетание можно назначить команде.
    static func problem(_ binding: HotkeyBinding, for action: HotkeyAction,
                        in bindings: [HotkeyAction: HotkeyBinding]) -> String? {
        guard binding.isAcceptable else {
            return String(localized: "Use ⌘ or ⌃ together with another modifier, or with a function key.")
        }
        if let other = bindings.first(where: { $0.key != action && $0.value.keyCode == binding.keyCode && $0.value.modifiers == binding.modifiers }) {
            return String(localized: "This shortcut is already used by “\(other.key.title)”.")
        }
        return nil
    }
}
