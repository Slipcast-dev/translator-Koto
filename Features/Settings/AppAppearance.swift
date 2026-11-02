import AppKit
import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Raw values — постоянный формат настройки; русские подписи можно менять независимо от хранения.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let preferenceKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
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
/// Тема задаётся только через NSApp.appearance. Параллельный preferredColorScheme не снимается
/// при возврате к nil и оставлял окно наполовину светлым, наполовину тёмным; значение nil
/// у NSApp.appearance, напротив, надёжно следует за системной темой, в том числе при её смене.
private struct KotoAppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.preferenceKey) private var selection = AppAppearance.system.rawValue

    func body(content: Content) -> some View {
        content
            .onChange(of: selection, initial: true) { _, newValue in
                let native = AppAppearance.resolve(newValue).nativeAppearance
                NSApp.appearance = native
                // Уже открытые окна могли получить явный appearance раньше: сбрасываем его.
                for window in NSApp.windows { window.appearance = nil }
            }
    }
}

extension View {
    func kotoAppearance() -> some View {
        modifier(KotoAppearanceModifier())
    }
}
