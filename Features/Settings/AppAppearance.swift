import AppKit
import SwiftUI

/// Raw values — постоянный формат настройки; русские подписи можно менять независимо от хранения.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let preferenceKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Системная"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Неизвестное значение из старой/повреждённой настройки безопасно возвращает системную тему.
    static func resolve(_ rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .system
    }
}

/// Модификатор подключён ко всем сценам, поэтому тема обновляется и в уже открытых окнах.
private struct KotoAppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.preferenceKey) private var selection = AppAppearance.system.rawValue

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(AppAppearance.resolve(selection).colorScheme)
            .onChange(of: selection, initial: true) { _, newValue in
                // NSApp.appearance включает нативные части окна, не охваченные preferredColorScheme.
                NSApp.appearance = AppAppearance.resolve(newValue).nativeAppearance
            }
    }
}

extension View {
    func kotoAppearance() -> some View {
        modifier(KotoAppearanceModifier())
    }
}
