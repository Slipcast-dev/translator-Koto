import Foundation
import CoreGraphics

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Ошибки захвата не содержат текст, пути чужих окон или сырые системные сообщения.
enum CaptureFailure: Error, LocalizedError, Equatable, Sendable {
    case accessibilityRequired, screenRequired, noApplication, noSelection, secureField
    case cancelled, invalidRegion, noText, unavailable, clipboardChanged, tooLong
    var errorDescription: String? {
        switch self {
        case .accessibilityRequired: String(localized: "Allow Koto accessibility access in Privacy & Security, then try again.")
        case .screenRequired: String(localized: "Allow Koto to record the screen in macOS privacy settings, then try again. You may need to restart Koto.")
        case .noApplication: String(localized: "First select text in another app.")
        case .noSelection: String(localized: "The app did not provide selected text. Use Services → Translate in Koto in the source app, or capture a screen region with OCR.")
        case .secureField: String(localized: "Capturing protected fields is disabled.")
        case .cancelled: String(localized: "Capture cancelled.")
        case .invalidRegion: String(localized: "Select a region of at least 8 × 8 points within one screen.")
        case .noText: String(localized: "No text was found in the selected region.")
        case .unavailable: String(localized: "Unable to retrieve the content. Try again in the source app.")
        case .clipboardChanged: String(localized: "The clipboard or active app changed. Try capturing again.")
        case .tooLong: String(localized: "The selection exceeds the \(AppLocalization.number(TranslationRequest.characterLimit))-character limit.")
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
