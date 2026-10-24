import AppKit
import Foundation

enum CaptureTestError: Error { case assertion(String) }

/// Геометрия проверяется в точках с независимо заданными ожидаемыми координатами.
/// Clipboard использует отдельный именованный pasteboard и не читает пользовательский general.
@main
struct CaptureTests {
    static func main() async throws {
        // Первый запуск Vision может компилировать системную модель. Watchdog не даёт CI зависнуть.
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
            FileHandle.standardError.write(Data("Capture tests exceeded 120 seconds.\n".utf8))
            exit(124)
        }
        var passed: [String] = []
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw CaptureTestError.assertion(name) }
            passed.append(name)
        }
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selected = CGRect(x: 100, y: 600, width: 400, height: 100)
        try check(try CaptureGeometry.sourceRect(selection: selected, screen: primary)
                  == CGRect(x: 100, y: 200, width: 400, height: 100), "primary display top-left conversion")
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        try check(try CaptureGeometry.sourceRect(selection: CGRect(x: -1800, y: 300, width: 800, height: 200), screen: left)
                  == CGRect(x: 120, y: 380, width: 800, height: 200), "negative origin display conversion")
        let above = CGRect(x: 200, y: 900, width: 1200, height: 800)
        try check(try CaptureGeometry.sourceRect(selection: CGRect(x: 300, y: 1400, width: 600, height: 200), screen: above)
                  == CGRect(x: 100, y: 100, width: 600, height: 200), "display above primary conversion")
        try check(try CaptureGeometry.sourceRect(selection: CGRect(x: 1300, y: 500, width: 400, height: 100), screen: primary).width
                  == 140, "region clipped to one display")
        do {
            _ = try CaptureGeometry.sourceRect(selection: CGRect(x: 0, y: 0, width: 3, height: 20), screen: primary)
            throw CaptureTestError.assertion("tiny region accepted")
        } catch CaptureFailure.invalidRegion { passed.append("tiny region rejected") }
        try check(CaptureGeometry.appKitRect(fromAX: CGRect(x: -40, y: 100, width: 100, height: 30), primaryHeight: 900)
                  == CGRect(x: -40, y: 770, width: 100, height: 30), "AX global coordinates conversion")
        let frame = CaptureGeometry.panelFrame(anchor: CGRect(x: -100, y: -200, width: 0, height: 0),
                  size: CGSize(width: 460, height: 440), visible: CGRect(x: -1920, y: -180, width: 1920, height: 1000))
        try check(CGRect(x: -1920, y: -180, width: 1920, height: 1000).contains(frame), "lens stays inside secondary display")
        let small = CaptureGeometry.panelFrame(anchor: .zero, size: CGSize(width: 460, height: 440),
                                              visible: CGRect(x: 0, y: 0, width: 320, height: 300))
        try check(small.size == CGSize(width: 320, height: 300), "lens clamps to narrow screen")

        let clipboard = NSPasteboard(name: NSPasteboard.Name("dev.slipcast.koto.tests." + UUID().uuidString))
        defer { clipboard.releaseGlobally() }
        clipboard.clearContents()
        clipboard.setString("The cat is sleeping on the chair.", forType: .string)
        let generalGeneration = NSPasteboard.general.changeCount
        let provider = CaptureServiceProvider()
        var received: String?
        provider.receive = { received = $0 }
        var serviceError: NSString?
        provider.translateSelection(clipboard, userData: nil, error: &serviceError)
        try check(received == "The cat is sleeping on the chair." && serviceError == nil,
                  "service receives selected text from dedicated pasteboard")
        try check(NSPasteboard.general.changeCount == generalGeneration, "service does not write general clipboard")
        received = nil
        clipboard.clearContents()
        clipboard.setString("   ", forType: .string)
        provider.translateSelection(clipboard, userData: nil, error: &serviceError)
        try check(received == nil && serviceError != nil, "service rejects empty selection")
        clipboard.clearContents()
        clipboard.setString(String(repeating: "a", count: 20_001), forType: .string)
        serviceError = nil
        provider.translateSelection(clipboard, userData: nil, error: &serviceError)
        try check(received == nil && serviceError != nil, "service rejects oversized selection")

        // Изображение создаётся из открытых контрольных фраз, без снимка пользовательского экрана.
        let image = NSImage(size: CGSize(width: 1200, height: 360))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 1200, height: 360).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black
        ]
        ("The cat is sleeping on the chair." as NSString).draw(at: CGPoint(x: 32, y: 240), withAttributes: attrs)
        ("Good morning from Koto." as NSString).draw(at: CGPoint(x: 32, y: 130), withAttributes: attrs)
        image.unlockFocus()
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw CaptureTestError.assertion("fixture image")
        }
        let text = try await ScreenOCRService.recognizeImage(cgImage)
        try check(text.contains("The cat is sleeping on the chair.") && text.contains("Good morning from Koto."),
                  "real Vision recognizes fixture")
        guard let firstLine = text.range(of: "The cat"), let secondLine = text.range(of: "Good morning") else {
            throw CaptureTestError.assertion("OCR line ranges")
        }
        try check(firstLine.lowerBound < secondLine.lowerBound, "OCR lines read from top to bottom")
        let blank = NSImage(size: CGSize(width: 400, height: 200))
        blank.lockFocus(); NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 400, height: 200).fill(); blank.unlockFocus()
        var blankRect = CGRect(origin: .zero, size: blank.size)
        guard let blankCG = blank.cgImage(forProposedRect: &blankRect, context: nil, hints: nil) else {
            throw CaptureTestError.assertion("blank fixture")
        }
        do {
            _ = try await ScreenOCRService.recognizeImage(blankCG)
            throw CaptureTestError.assertion("blank OCR accepted")
        } catch CaptureFailure.noText { passed.append("blank image reports no text") }
        let report: [String: Any] = ["status": "passed", "count": passed.count, "tests": passed, "ocr_fixture_output": text]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
