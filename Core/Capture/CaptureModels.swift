import Foundation
import CoreGraphics

/// Ошибки захвата не содержат текст, пути чужих окон или сырые системные сообщения.
enum CaptureFailure: Error, LocalizedError, Equatable, Sendable {
    case accessibilityRequired, screenRequired, noApplication, noSelection, secureField
    case cancelled, invalidRegion, noText, unavailable, clipboardChanged, tooLong
    var errorDescription: String? {
        switch self {
        case .accessibilityRequired: "Разрешите Koto доступ в «Конфиденциальность и безопасность → Управление устройством и доступ к данным» (на macOS 26 — «Универсальный доступ»), затем повторите команду."
        case .screenRequired: "Разрешите Koto запись экрана в настройках конфиденциальности macOS, затем повторите команду. Может потребоваться перезапуск Koto."
        case .noApplication: "Сначала выделите текст в другом приложении."
        case .noSelection: "Приложение не предоставило выделенный текст. Используйте «Службы → Перевести в Koto» в исходном приложении или OCR области."
        case .secureField: "Захват защищённых полей отключён."
        case .cancelled: "Захват отменён."
        case .invalidRegion: "Выберите область не меньше 8 × 8 точек в пределах одного экрана."
        case .noText: "В выбранной области текст не найден."
        case .unavailable: "Не удалось получить содержимое. Повторите действие в исходном приложении."
        case .clipboardChanged: "Буфер обмена или активное приложение изменились. Повторите захват."
        case .tooLong: "Выделение превышает лимит 20 000 символов."
        }
    }
}

/// Точки AppKit имеют начало снизу слева; ScreenCaptureKit использует локальное начало сверху.
enum CaptureGeometry {
    static func sourceRect(selection: CGRect, screen: CGRect) throws -> CGRect {
        let clipped = selection.standardized.intersection(screen)
        guard !clipped.isNull, clipped.width >= 8, clipped.height >= 8 else {
            throw CaptureFailure.invalidRegion
        }
        return CGRect(x: clipped.minX - screen.minX, y: screen.maxY - clipped.maxY,
                      width: clipped.width, height: clipped.height)
    }

    static func appKitRect(fromAX rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func panelFrame(anchor: CGRect, size: CGSize, visible: CGRect) -> CGRect {
        let width = min(size.width, visible.width), height = min(size.height, visible.height)
        return CGRect(x: min(max(anchor.minX, visible.minX), visible.maxX - width),
                      y: min(max(anchor.minY - height - 10, visible.minY), visible.maxY - height),
                      width: width, height: height)
    }
}

struct CapturedText {
    let text: String
    let anchor: CGRect
}
